import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/sharing/reel_share.dart';

class _Auth extends MockFirebaseAuth {
  User? _user = MockUser(uid: 'viewer-a', isEmailVerified: true);
  final _changes = StreamController<User?>.broadcast(sync: true);
  @override
  User? get currentUser => _user;
  @override
  Stream<User?> userChanges() => _changes.stream;
  void change(String? uid) {
    _user = uid == null ? null : MockUser(uid: uid, isEmailVerified: true);
    _changes.add(_user);
  }

  Future<void> close() => _changes.close();
}

Map<Object?, Object?> _view({String id = 'reel_1', int? expiresAt}) => {
  'schemaVersion': 2,
  'reel': {
    'id': id,
    'authorId': 'private-author',
    'authorName': 'PRIVATE AUTHOR',
    'media': {
      'kind': 'video',
      'contentType': 'video/mp4',
      'size': 4096,
      'generation': '7',
      'durationMs': 10000,
    },
    'backingAudio': null,
    'composition': const ReelComposition(
      trimStartMs: 0,
      trimEndMs: 10000,
      caption: 'PRIVATE CAPTION https://storage.test/?token=DO_NOT_SHARE',
    ).toWire(),
    'publishedAtMillis': 1725000000000,
    'sortKey': '1725000000000_$id',
    'availability': {
      'schemaVersion': 1,
      'availabilityHours': expiresAt == null ? 'permanent' : 24,
      'expiresAtMillis': expiresAt,
    },
    'likeCount': 1,
    'commentCount': 0,
    'callerLiked': false,
  },
  'comments': <Object?>[],
  'commentsTruncated': false,
  'nextCommentCursor': null,
};

Future<void> _pump(
  WidgetTester tester, {
  required ReelService service,
  required ReelShareInvoker share,
  required ReelLinkClipboardWriter clipboard,
  String reelId = 'reel_1',
  DateTime Function()? now,
  Size size = const Size(390, 844),
  Locale locale = const Locale('en'),
  ThemeData? theme,
  double textScale = 1,
  bool doubleOpen = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.darkTheme,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () {
              final first = showReelShareSheet(
                context,
                reelId: reelId,
                service: service,
                shareInvoker: share,
                clipboardWriter: clipboard,
                now: now,
              );
              if (doubleOpen) {
                final second = showReelShareSheet(
                  context,
                  reelId: reelId,
                  service: service,
                  shareInvoker: share,
                  clipboardWriter: clipboard,
                  now: now,
                );
                expect(identical(first, second), isTrue);
              }
              unawaited(first);
            },
            child: const Text('Open test sheet'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open test sheet'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  setUp(ReelService.clearAllMediaAccessCaches);

  testWidgets(
    'read authorization precedes explicit ID-only share/copy with no view count or media',
    (tester) async {
      final auth = _Auth();
      final ready = Completer<Map<Object?, Object?>>();
      final calls = <String>[];
      final shared = <ShareParams>[];
      final copied = <String>[];
      final service = ReelService(
        auth: auth,
        callableInvoker: (name, payload) {
          calls.add(name);
          expect(name, 'getReelViewV2');
          expect(payload, {
            'reelId': 'reel_1',
            'commentLimit': 1,
            'commentCursor': null,
          });
          return ready.future;
        },
      );
      await _pump(
        tester,
        service: service,
        doubleOpen: true,
        share: (params) async {
          shared.add(params);
          return const ShareResult('', ShareResultStatus.dismissed);
        },
        clipboard: (text) async {
          copied.add(text);
        },
      );
      expect(find.byKey(const ValueKey('reel-share-sheet')), findsOneWidget);
      expect(find.byKey(const ValueKey('reel-share-platform')), findsNothing);
      expect(shared, isEmpty);
      ready.complete(_view());
      await tester.pumpAndSettle();
      expect(find.textContaining('PRIVATE'), findsNothing);
      expect(shared, isEmpty);
      await tester.tap(find.byKey(const ValueKey('reel-share-platform')));
      await tester.pump();
      expect(shared, hasLength(1));
      final params = shared.single;
      expect(params.text, 'https://app.yovoice.app/?reel=reel_1');
      expect(params.uri, isNull);
      expect(params.files, isNull);
      expect(params.title, isNull);
      expect(params.subject, isNull);
      expect(params.downloadFallbackEnabled, isFalse);
      expect(params.mailToFallbackEnabled, isFalse);
      expect(params.sharePositionOrigin!.width, greaterThan(0));
      expect(params.sharePositionOrigin!.height, greaterThan(0));
      expect(
        copied,
        isEmpty,
        reason: 'Dismissing share must not overwrite the clipboard.',
      );
      expect(find.text('Reel link copied.'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('reel-share-copy')));
      await tester.pump();
      expect(copied, ['https://app.yovoice.app/?reel=reel_1']);
      expect(find.text('Reel link copied.'), findsOneWidget);
      expect(calls, ['getReelViewV2']);
      await tester.pumpWidget(const SizedBox.shrink());
      await auth.close();
    },
  );

  testWidgets(
    'denied, nonexistent, blocked and malformed responses reveal nothing',
    (tester) async {
      for (final error in [
        FirebaseFunctionsException(
          code: 'permission-denied',
          message: 'PRIVATE AUTHOR',
        ),
        FirebaseFunctionsException(
          code: 'not-found',
          message: 'PRIVATE CAPTION',
        ),
        FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'blocked account',
        ),
        const FormatException('https://private.test/?token=secret'),
      ]) {
        final auth = _Auth();
        final service = ReelService(
          auth: auth,
          callableInvoker: (_, _) async => throw error,
        );
        await _pump(
          tester,
          service: service,
          share: (_) async => throw StateError('Must not share'),
          clipboard: (_) async => throw StateError('Must not copy'),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('This Reel is unavailable right now.'),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('reel-share-platform')), findsNothing);
        expect(find.byKey(const ValueKey('reel-share-copy')), findsNothing);
        expect(find.textContaining('PRIVATE'), findsNothing);
        expect(find.textContaining('secret'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await auth.close();
      }
    },
  );

  testWidgets('A→B and A→null→A invalidate pending share authorization', (
    tester,
  ) async {
    for (final identities in [
      <String?>['viewer-b'],
      <String?>[null, 'viewer-a'],
    ]) {
      final auth = _Auth();
      final ready = Completer<Map<Object?, Object?>>();
      var shared = 0;
      final service = ReelService(
        auth: auth,
        callableInvoker: (_, _) => ready.future,
      );
      await _pump(
        tester,
        service: service,
        share: (_) async {
          shared++;
          return const ShareResult('', ShareResultStatus.success);
        },
        clipboard: (_) async {
          shared++;
        },
      );
      for (final uid in identities) {
        auth.change(uid);
      }
      ready.complete(_view());
      await tester.pumpAndSettle();
      expect(find.text('Sign in to open this Reel.'), findsOneWidget);
      expect(find.byKey(const ValueKey('reel-share-platform')), findsNothing);
      expect(shared, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await auth.close();
    }
  });

  testWidgets(
    'an expired local authorization cannot dispatch even before timer paints',
    (tester) async {
      final auth = _Auth();
      var now = DateTime.utc(2026, 9, 11);
      var shared = 0;
      final service = ReelService(
        auth: auth,
        callableInvoker: (_, _) async => _view(),
      );
      await _pump(
        tester,
        service: service,
        now: () => now,
        share: (_) async {
          shared++;
          return const ShareResult('', ShareResultStatus.success);
        },
        clipboard: (_) async {
          shared++;
        },
      );
      await tester.pumpAndSettle();
      now = now.add(const Duration(seconds: 31));
      await tester.tap(find.byKey(const ValueKey('reel-share-copy')));
      await tester.tap(find.byKey(const ValueKey('reel-share-platform')));
      expect(shared, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await auth.close();
    },
  );

  testWidgets(
    'platform failure is safe and copy is a separate deliberate fallback',
    (tester) async {
      final auth = _Auth();
      final copied = <String>[];
      final service = ReelService(
        auth: auth,
        callableInvoker: (_, _) async => _view(),
      );
      await _pump(
        tester,
        service: service,
        share: (_) async => throw PlatformException(
          code: 'unavailable',
          message: 'PRIVATE transport',
        ),
        clipboard: (text) async {
          copied.add(text);
        },
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reel-share-platform')));
      await tester.pumpAndSettle();
      expect(
        find.text('Sharing is unavailable here. Copy the link instead.'),
        findsOneWidget,
      );
      expect(find.textContaining('PRIVATE'), findsNothing);
      expect(copied, isEmpty);
      await tester.tap(find.byKey(const ValueKey('reel-share-copy')));
      await tester.pumpAndSettle();
      expect(copied, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
      await auth.close();
    },
  );

  testWidgets(
    'an unavailable SDK result is neutral and offers copy without claiming failure or delivery',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final auth = _Auth();
      final copied = <String>[];
      final service = ReelService(
        auth: auth,
        callableInvoker: (_, _) async => _view(),
      );
      await _pump(
        tester,
        service: service,
        share: (_) async =>
            const ShareResult('', ShareResultStatus.unavailable),
        clipboard: (text) async => copied.add(text),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reel-share-platform')));
      await tester.pumpAndSettle();
      expect(
        find.text('Sharing could not be confirmed. You can copy the link.'),
        findsOneWidget,
      );
      expect(
        find.text('Sharing is unavailable here. Copy the link instead.'),
        findsNothing,
      );
      expect(
        tester
            .getSemantics(
              find.text(
                'Sharing could not be confirmed. You can copy the link.',
              ),
            )
            .getSemanticsData()
            .flagsCollection
            .isLiveRegion,
        isTrue,
        reason: 'An unknown outcome is neutral, not an assertive failure.',
      );
      expect(copied, isEmpty);
      expect(find.text('Reel link copied.'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('reel-share-copy')));
      await tester.pumpAndSettle();
      expect(copied, ['https://app.yovoice.app/?reel=reel_1']);
      expect(find.text('Reel link copied.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await auth.close();
      semantics.dispose();
    },
  );

  testWidgets(
    'share and copy errors announce assertively, copied remains one polite status',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final announcements = <Map<Object?, Object?>>[];
      tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(SystemChannels.accessibility, (
            message,
          ) async {
            if (message is Map && message['type'] == 'announce') {
              announcements.add(message['data'] as Map<Object?, Object?>);
            }
            return null;
          });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockDecodedMessageHandler<Object?>(
              SystemChannels.accessibility,
              null,
            ),
      );
      final auth = _Auth();
      var copyAttempts = 0;
      final service = ReelService(
        auth: auth,
        callableInvoker: (_, _) async => _view(),
      );
      await _pump(
        tester,
        service: service,
        share: (_) async => throw PlatformException(code: 'unavailable'),
        clipboard: (_) async {
          if (++copyAttempts == 1) throw PlatformException(code: 'unavailable');
        },
      );
      await tester.pumpAndSettle();
      for (final action in ['platform', 'copy']) {
        announcements.clear();
        await tester.tap(find.byKey(ValueKey('reel-share-$action')));
        await tester.pumpAndSettle();
        final message = action == 'platform'
            ? 'Sharing is unavailable here. Copy the link instead.'
            : 'The link could not be copied. Try again.';
        expect(announcements, hasLength(1));
        expect(announcements.single['message'], message);
        expect(
          announcements.single['assertiveness'],
          Assertiveness.assertive.index,
        );
        expect(
          tester
              .getSemantics(find.text(message))
              .getSemanticsData()
              .flagsCollection
              .isLiveRegion,
          isFalse,
          reason: 'An error must not compete for the shared polite channel.',
        );
        await tester.pump();
        expect(announcements, hasLength(1));
      }
      announcements.clear();
      await tester.tap(find.byKey(const ValueKey('reel-share-copy')));
      await tester.pumpAndSettle();
      expect(
        tester
            .getSemantics(find.text('Reel link copied.'))
            .getSemanticsData()
            .flagsCollection
            .isLiveRegion,
        isTrue,
      );
      expect(announcements, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await auth.close();
      semantics.dispose();
    },
  );

  testWidgets(
    'share sheet fits narrow/tablet/desktop, Polish and RTL at 200%',
    (tester) async {
      for (final locale in const [Locale('en'), Locale('pl'), Locale('ar')]) {
        for (final size in const [
          Size(320, 568),
          Size(768, 1024),
          Size(1440, 900),
        ]) {
          final auth = _Auth();
          final service = ReelService(
            auth: auth,
            callableInvoker: (_, _) async => _view(),
          );
          await _pump(
            tester,
            service: service,
            size: size,
            locale: locale,
            textScale: 2,
            theme: locale.languageCode == 'pl'
                ? AppTheme.lightTheme
                : AppTheme.darkTheme,
            share: (_) async =>
                const ShareResult('', ShareResultStatus.unavailable),
            clipboard: (_) async {},
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('reel-share-platform')));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('reel-share-copy')), findsOneWidget);
          expect(
            find.text(switch (locale.languageCode) {
              'pl' =>
                'Nie można potwierdzić udostępnienia. Możesz skopiować link.',
              'ar' => 'تعذر تأكيد المشاركة. يمكنك نسخ الرابط.',
              _ => 'Sharing could not be confirmed. You can copy the link.',
            }),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull, reason: '$locale $size');
          await tester.pumpWidget(const SizedBox.shrink());
          await auth.close();
        }
      }
    },
  );
}
