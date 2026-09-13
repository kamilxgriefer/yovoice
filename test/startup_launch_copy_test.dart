import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yovoice/core/localization/translations/translations_startup.dart';
import 'package:yovoice/features/auth/presentation/widgets/startup_launch_copy.dart';

/// The actual SharedPreferences cache supplies reads; only the persistence
/// boundary is controlled, without adding a new platform dependency.
class _WriteControlledPreferences implements SharedPreferences {
  _WriteControlledPreferences(this.delegate, this.write);

  final SharedPreferences delegate;
  final Future<bool> Function(String key, String value) write;
  final writes = <(String, String)>[];

  @override
  Object? get(String key) => delegate.get(key);

  @override
  Future<bool> setString(String key, String value) {
    writes.add((key, value));
    return write(key, value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'four fresh launches select four phrases then wrap to the first',
    () async {
      final selected = <String>[];
      for (var launch = 0; launch < 5; launch++) {
        final session = StartupHeadlineSession();
        await session.prepare();
        selected.add(session.headlineKey);
        final stored = await SharedPreferences.getInstance();
        expect(
          stored.getString(StartupHeadlineSession.preferenceKey),
          session.headlineKey,
        );
      }

      expect(selected, [
        ...startupHeadlineTranslationKeys,
        startupHeadlineTranslationKeys.first,
      ]);
    },
  );

  test('every valid persisted phrase selects its next complete key', () async {
    for (
      var index = 0;
      index < startupHeadlineTranslationKeys.length;
      index++
    ) {
      SharedPreferences.setMockInitialValues({
        StartupHeadlineSession.preferenceKey:
            startupHeadlineTranslationKeys[index],
      });
      final session = StartupHeadlineSession();
      await session.prepare();

      expect(
        session.headlineKey,
        startupHeadlineTranslationKeys[(index + 1) %
            startupHeadlineTranslationKeys.length],
      );
    }
  });

  test(
    'concurrent and repeated preparation performs one read and one write',
    () async {
      final realPreferences = await SharedPreferences.getInstance();
      final stored = _WriteControlledPreferences(
        realPreferences,
        realPreferences.setString,
      );
      final gate = Completer<SharedPreferences>();
      var reads = 0;
      final session = StartupHeadlineSession(
        preferences: () {
          reads++;
          return gate.future;
        },
      );

      final first = session.prepare();
      final second = session.prepare();
      expect(identical(first, second), isTrue);
      expect(reads, 1);
      expect(stored.writes, isEmpty);
      gate.complete(stored);
      await Future.wait([first, second]);
      final selected = session.headlineKey;
      await session.prepare();
      for (var rebuild = 0; rebuild < 10; rebuild++) {
        expect(session.headlineKey, selected);
      }
      expect(reads, 1);
      expect(stored.writes, [(StartupHeadlineSession.preferenceKey, selected)]);
    },
  );

  test(
    'late preferences cannot replace a phrase that is already visible',
    () async {
      SharedPreferences.setMockInitialValues({
        StartupHeadlineSession.preferenceKey: startupHeadlineTranslationKeys[1],
      });
      final realPreferences = await SharedPreferences.getInstance();
      final gate = Completer<SharedPreferences>();
      final session = StartupHeadlineSession(preferences: () => gate.future);

      final prepared = session.prepare();
      final firstVisible = session.headlineKey;
      expect(firstVisible, startupHeadlineTranslationKeys.first);
      gate.complete(realPreferences);
      await prepared;
      expect(session.headlineKey, firstVisible);
      expect(
        realPreferences.getString(StartupHeadlineSession.preferenceKey),
        firstVisible,
      );

      final nextLaunch = StartupHeadlineSession();
      await nextLaunch.prepare();
      expect(nextLaunch.headlineKey, startupHeadlineTranslationKeys[1]);
    },
  );

  test(
    'reading before preparation locks one headline for the entire launch',
    () async {
      SharedPreferences.setMockInitialValues({
        StartupHeadlineSession.preferenceKey: startupHeadlineTranslationKeys[2],
      });
      final session = StartupHeadlineSession();
      final initiallyShown = session.headlineKey;
      await session.prepare();
      expect(session.headlineKey, initiallyShown);
      expect(initiallyShown, startupHeadlineTranslationKeys.first);
    },
  );

  for (final invalid in <Object>[
    '',
    'removed-or-unknown-phrase',
    'Tu zaczyna się rozmowa.',
    42,
    true,
    <String>['unexpected', 'list'],
  ]) {
    test(
      'unrecognized stored value ${invalid.runtimeType}: $invalid is safe',
      () async {
        SharedPreferences.setMockInitialValues({
          StartupHeadlineSession.preferenceKey: invalid,
        });
        final session = StartupHeadlineSession();
        await expectLater(session.prepare(), completes);
        expect(session.headlineKey, startupHeadlineTranslationKeys.first);
        final stored = await SharedPreferences.getInstance();
        expect(
          stored.getString(StartupHeadlineSession.preferenceKey),
          startupHeadlineTranslationKeys.first,
        );
      },
    );
  }

  test(
    'an unavailable preferences read falls back without retries or error',
    () async {
      var reads = 0;
      final session = StartupHeadlineSession(
        preferences: () async {
          reads++;
          throw StateError('unavailable local preferences');
        },
      );
      await expectLater(session.prepare(), completes);
      expect(session.headlineKey, startupHeadlineTranslationKeys.first);
      await expectLater(session.prepare(), completes);
      expect(reads, 1);
    },
  );

  test('a synchronous preferences factory error is also contained', () async {
    final session = StartupHeadlineSession(
      preferences: () => throw StateError('broken preferences factory'),
    );
    await expectLater(session.prepare(), completes);
    expect(session.headlineKey, startupHeadlineTranslationKeys.first);
  });

  for (final synchronous in [false, true]) {
    test(
      'a ${synchronous ? 'sync' : 'async'} write failure preserves the selected phrase',
      () async {
        SharedPreferences.setMockInitialValues({
          StartupHeadlineSession.preferenceKey:
              startupHeadlineTranslationKeys.first,
        });
        final realPreferences = await SharedPreferences.getInstance();
        final stored = _WriteControlledPreferences(realPreferences, (_, __) {
          if (synchronous) throw StateError('disk full');
          return Future<bool>.error(StateError('disk full'));
        });
        final session = StartupHeadlineSession(preferences: () async => stored);
        await expectLater(session.prepare(), completes);
        expect(session.headlineKey, startupHeadlineTranslationKeys[1]);
        await expectLater(session.prepare(), completes);
        expect(stored.writes, hasLength(1));
      },
    );
  }

  test('a false write acknowledgement does not change copy or retry', () async {
    SharedPreferences.setMockInitialValues({
      StartupHeadlineSession.preferenceKey:
          startupHeadlineTranslationKeys.first,
    });
    final stored = _WriteControlledPreferences(
      await SharedPreferences.getInstance(),
      (_, __) async => false,
    );
    final session = StartupHeadlineSession(preferences: () async => stored);
    await session.prepare();
    expect(session.headlineKey, startupHeadlineTranslationKeys[1]);
    await session.prepare();
    expect(stored.writes, hasLength(1));
  });

  test(
    'a pending disk write never prevents reading the selected headline',
    () async {
      SharedPreferences.setMockInitialValues({
        StartupHeadlineSession.preferenceKey:
            startupHeadlineTranslationKeys.first,
      });
      final writeStarted = Completer<void>();
      final writeFinished = Completer<bool>();
      final stored = _WriteControlledPreferences(
        await SharedPreferences.getInstance(),
        (_, __) {
          writeStarted.complete();
          return writeFinished.future;
        },
      );
      final session = StartupHeadlineSession(preferences: () async => stored);
      var preparationFinished = false;
      final prepared = session.prepare().then(
        (_) => preparationFinished = true,
      );
      await writeStarted.future;
      expect(preparationFinished, isFalse);
      expect(session.headlineKey, startupHeadlineTranslationKeys[1]);
      writeFinished.complete(true);
      await prepared;
      expect(session.headlineKey, startupHeadlineTranslationKeys[1]);
    },
  );

  test(
    'rotation writes only its own key and preserves language/auth preferences',
    () async {
      SharedPreferences.setMockInitialValues({
        'app.language': 'polish',
        'tour.account.version': 7,
        'unrelated.setting': true,
      });
      final session = StartupHeadlineSession();
      await session.prepare();
      final stored = await SharedPreferences.getInstance();
      expect(stored.getString('app.language'), 'polish');
      expect(stored.getInt('tour.account.version'), 7);
      expect(stored.getBool('unrelated.setting'), isTrue);
      expect(stored.getKeys(), {
        'app.language',
        'tour.account.version',
        'unrelated.setting',
        StartupHeadlineSession.preferenceKey,
      });
    },
  );

  test(
    'main starts headline preparation without awaiting a new startup gate',
    () {
      final source = File('lib/main.dart').readAsStringSync();
      expect(source, contains('unawaited(StartupLaunchCopy.prepare());'));
      expect(source, isNot(contains('await StartupLaunchCopy.prepare()')));
      expect(
        source.indexOf('unawaited(StartupLaunchCopy.prepare());'),
        lessThan(
          source.indexOf('await AppPreferencesController.instance.load()'),
        ),
        reason: 'the rotation shares the existing preference read',
      );
      expect(source, isNot(contains('Future.delayed')));
    },
  );
}
