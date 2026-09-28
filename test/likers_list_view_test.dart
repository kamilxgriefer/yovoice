import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/likers/data/models/likers_page.dart';
import 'package:yovoice/features/likers/data/models/likers_target.dart';
import 'package:yovoice/features/likers/presentation/widgets/likers_list_view.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';
import 'package:yovoice/shared/widgets/identity/yo_vip_rosette.dart';

import 'support/likers_fixtures.dart';

const _moment = VoiceMomentLikersTarget('m1');

/// Settles frames AND the identity repository's batching timer.
Future<void> settleAll(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 20));
  await tester.pumpAndSettle();
}

const _message = ServerMessageReactorsTarget('s1', 'ch1', 'msg1');

void main() {
  late PublicIdentityRepository repository;

  setUp(() => repository = identityRepository(vip: {'marta'}));

  Future<void> pumpList(
    WidgetTester tester,
    ScriptedLikers script, {
    LikersTarget target = _moment,
    int total = 2,
    Map<String, int> reactionCounts = const {},
    VoidCallback? onAccessRequired,
    VoidCallback? onClose,
    LikerOpener? onOpenLiker,
    Size size = const Size(390, 844),
    double textScale = 1,
    TextDirection? direction,
    bool settle = true,
  }) async {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      likersHost(
        Scaffold(
          body: LikersListView(
            target: target,
            totalCount: total,
            reactionCounts: reactionCounts,
            service: script.service,
            viewerId: 'me',
            onAccessRequired: onAccessRequired,
            onClose: onClose,
            onOpenLiker: onOpenLiker,
            identityRepository: repository,
          ),
        ),
        textScale: textScale,
        direction: direction,
      ),
    );
    if (settle) await settleAll(tester);
  }

  List<String> captureAnnouncements(WidgetTester tester) {
    final captured = <String>[];
    tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(
      SystemChannels.accessibility,
      (message) async {
        if (message is Map && message['type'] == 'announce') {
          captured.add((message['data'] as Map)['message'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(
            SystemChannels.accessibility,
            null,
          ),
    );
    return captured;
  }

  testWidgets('first page loads behind a STATIC skeleton (no ticker)', (
    tester,
  ) async {
    final pending = Completer<Object?>();
    final script = ScriptedLikers([pending]);
    await pumpList(tester, script, settle: false);
    await tester.pump();
    expect(find.byKey(const ValueKey('likers-skeleton')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const ValueKey('likers-skeleton')), findsOneWidget);
    pending.complete(pageWire([likerWire('julia', 'Julia Nowak')]));
    await settleAll(tester);
    expect(find.byKey(const ValueKey('likers-skeleton')), findsNothing);
    expect(find.text('Julia Nowak'), findsOneWidget);
  });

  testWidgets('rows: header total, VIP rosette, self reads "You", hearts', (
    tester,
  ) async {
    final announcements = captureAnnouncements(tester);
    final script = ScriptedLikers([
      pageWire([
        likerWire('julia', 'Julia Nowak'),
        likerWire('marta', 'Marta Wiśniewska'),
        likerWire('me', 'Kamil Jaguszewski'),
      ]),
    ]);
    await pumpList(tester, script, total: 3);
    expect(find.textContaining('Likes'), findsWidgets);
    expect(find.textContaining('· 3', findRichText: true), findsOneWidget);
    expect(find.text('Julia Nowak'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Kamil Jaguszewski'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('likers-row-marta')),
        matching: find.byType(YoVipRosette),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('likers-row-julia')),
        matching: find.byType(YoVipRosette),
      ),
      findsNothing,
    );
    expect(find.byIcon(Icons.favorite_rounded), findsNWidgets(3));
    expect(find.bySemanticsLabel(RegExp('Marta Wiśniewska')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'VIP')), findsWidgets);
    // Complete, nothing hidden: no partial footer, the quiet hint is there.
    expect(find.text('Some people aren\'t shown.'), findsNothing);
    expect(
      find.text('You can hide your own likes in Settings → Privacy.'),
      findsOneWidget,
    );
    expect(announcements, contains('Likes loaded: 3'));
    expect(script.calls.single.payload, {'momentId': 'm1'});
  });

  testWidgets('server rows carry the emoji and a reacted label', (
    tester,
  ) async {
    final script = ScriptedLikers([
      pageWire([
        likerWire('julia', 'Julia Nowak', reaction: '👍'),
        likerWire('natalia', 'Natalia Kowalczyk', reaction: '❤️'),
      ]),
    ]);
    await pumpList(
      tester,
      script,
      target: _message,
      reactionCounts: const {'👍': 1, '❤️': 1},
    );
    expect(find.textContaining('Reactions'), findsWidgets);
    expect(find.text('👍'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_rounded), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp('Julia Nowak, reacted 👍')),
      findsOneWidget,
    );
  });

  testWidgets('server tabs: All + emoji ordered by count; a tab filters', (
    tester,
  ) async {
    final script = ScriptedLikers([
      pageWire([likerWire('julia', 'Julia Nowak', reaction: '👍')]),
      pageWire([likerWire('marta', 'Marta Wiśniewska', reaction: '❤️')]),
      pageWire([likerWire('julia', 'Julia Nowak', reaction: '👍')]),
    ]);
    await pumpList(
      tester,
      script,
      target: _message,
      total: 12,
      reactionCounts: const {'😂': 3, '❤️': 4, '👍': 5},
    );
    final tabs = [
      'likers-tab-all',
      'likers-tab-👍',
      'likers-tab-❤️',
      'likers-tab-😂',
    ].map((key) => tester.getTopLeft(find.byKey(ValueKey(key))).dx).toList();
    expect(tabs, orderedEquals([...tabs]..sort()));
    expect(find.bySemanticsLabel('All: 12'), findsOneWidget);
    expect(find.bySemanticsLabel('❤️: 4'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('likers-tab-❤️')));
    await settleAll(tester);
    expect(script.calls[1].payload['emoji'], '❤️');
    expect(find.text('Marta Wiśniewska'), findsOneWidget);
    expect(find.text('Julia Nowak'), findsNothing);
    // 1 listed of the tab's 4: the partial footer uses the tab total.
    expect(find.text('Some people aren\'t shown.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('likers-tab-all')));
    await settleAll(tester);
    expect(script.calls[2].payload.containsKey('emoji'), isFalse);
  });

  testWidgets('one emoji needs no tab strip', (tester) async {
    final script = ScriptedLikers([
      pageWire([likerWire('julia', 'Julia Nowak', reaction: '👍')]),
    ]);
    await pumpList(
      tester,
      script,
      target: _message,
      total: 1,
      reactionCounts: const {'👍': 1},
    );
    expect(find.byKey(const ValueKey('likers-tab-all')), findsNothing);
  });

  testWidgets('empty: never says why, keeps the quiet hint', (tester) async {
    final announcements = captureAnnouncements(tester);
    final script = ScriptedLikers([pageWire(const [])]);
    await pumpList(tester, script, total: 4);
    expect(find.text('No one to show here.'), findsOneWidget);
    expect(
      find.text('You can hide your own likes in Settings → Privacy.'),
      findsOneWidget,
    );
    expect(announcements, contains('No one to show here.'));
  });

  testWidgets('partial footer only when complete and listed < total', (
    tester,
  ) async {
    final announcements = captureAnnouncements(tester);
    final script = ScriptedLikers([
      pageWire([likerWire('julia', 'Julia Nowak')], cursor: kTestCursor),
      pageWire([likerWire('piotr', 'Piotr Zieliński')]),
    ]);
    await pumpList(tester, script, total: 5);
    expect(find.text('Some people aren\'t shown.'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('likers-load-more')));
    await settleAll(tester);
    expect(script.calls[1].payload['cursor'], kTestCursor);
    expect(find.text('Piotr Zieliński'), findsOneWidget);
    expect(find.text('Some people aren\'t shown.'), findsOneWidget);
    expect(announcements, contains('Some people aren\'t shown.'));
  });

  testWidgets('empty pages auto-continue at most twice, then Load more', (
    tester,
  ) async {
    final script = ScriptedLikers([
      pageWire(const [], cursor: kTestCursor),
      pageWire(const [], cursor: kTestCursor2),
      pageWire(const [], cursor: kTestCursor),
      pageWire([likerWire('julia', 'Julia Nowak')]),
    ]);
    await pumpList(tester, script, total: 30);
    expect(script.calls, hasLength(3));
    expect(find.byKey(const ValueKey('likers-load-more')), findsOneWidget);
    expect(find.byKey(const ValueKey('likers-skeleton')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('likers-load-more')));
    await settleAll(tester);
    expect(script.calls, hasLength(4));
    expect(find.text('Julia Nowak'), findsOneWidget);
  });

  testWidgets('scrolling near the end loads the next page', (tester) async {
    final script = ScriptedLikers([
      pageWire([
        for (var i = 0; i < 20; i++) likerWire('u$i', 'Person $i'),
      ], cursor: kTestCursor),
      pageWire([likerWire('last', 'Last Person')]),
    ]);
    await pumpList(tester, script, total: 21);
    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await settleAll(tester);
    expect(script.calls, hasLength(2));
    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await settleAll(tester);
    expect(find.text('Last Person'), findsOneWidget);
  });

  testWidgets('error by failure type, then Try again recovers', (tester) async {
    final announcements = captureAnnouncements(tester);
    final script = ScriptedLikers([
      functionsError('unavailable'),
      pageWire([likerWire('julia', 'Julia Nowak')]),
    ]);
    await pumpList(tester, script);
    expect(find.text('Couldn\'t load this list. Try again.'), findsOneWidget);
    expect(announcements, contains('Couldn\'t load this list. Try again.'));
    await tester.tap(find.byKey(const ValueKey('likers-retry')));
    await settleAll(tester);
    expect(find.text('Julia Nowak'), findsOneWidget);
  });

  testWidgets('rate limited has its own message', (tester) async {
    final script = ScriptedLikers([functionsError('resource-exhausted')]);
    await pumpList(tester, script);
    expect(
      find.text('Too many requests. Try again in a minute.'),
      findsOneWidget,
    );
  });

  testWidgets('a failed next page keeps the rows and retries inline', (
    tester,
  ) async {
    final script = ScriptedLikers([
      pageWire([likerWire('julia', 'Julia Nowak')], cursor: kTestCursor),
      functionsError('internal'),
      pageWire([likerWire('piotr', 'Piotr Zieliński')]),
    ]);
    await pumpList(tester, script, total: 2);
    await tester.tap(find.byKey(const ValueKey('likers-load-more')));
    await settleAll(tester);
    expect(find.text('Julia Nowak'), findsOneWidget);
    expect(find.byKey(const ValueKey('likers-page-error')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('likers-retry')));
    await settleAll(tester);
    expect(script.calls.last.payload['cursor'], kTestCursor);
    expect(find.text('Piotr Zieliński'), findsOneWidget);
  });

  testWidgets('an invalid cursor restarts silently from page 1, once', (
    tester,
  ) async {
    final script = ScriptedLikers([
      pageWire([likerWire('julia', 'Julia Nowak')], cursor: kTestCursor),
      functionsError('invalid-argument'),
      pageWire([likerWire('julia', 'Julia Nowak')], cursor: kTestCursor2),
      functionsError('invalid-argument'),
    ]);
    await pumpList(tester, script, total: 3);
    await tester.tap(find.byKey(const ValueKey('likers-load-more')));
    await settleAll(tester);
    expect(script.calls[2].payload.containsKey('cursor'), isFalse);
    expect(find.text('Julia Nowak'), findsOneWidget);
    expect(find.byKey(const ValueKey('likers-page-error')), findsNothing);
    // A second invalid cursor is an ordinary error, not a loop.
    await tester.tap(find.byKey(const ValueKey('likers-load-more')));
    await settleAll(tester);
    expect(script.calls, hasLength(4));
    expect(find.byKey(const ValueKey('likers-page-error')), findsOneWidget);
  });

  testWidgets('unavailable content offers Close', (tester) async {
    var closed = 0;
    final script = ScriptedLikers([functionsError('permission-denied')]);
    await pumpList(tester, script, onClose: () => closed++);
    expect(find.text('This content is no longer available.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('likers-close')));
    expect(closed, 1);
  });

  testWidgets('switch off: the coming-soon state', (tester) async {
    final script = ScriptedLikers([
      functionsError('failed-precondition', reason: 'likersNotEnabled'),
    ]);
    await pumpList(tester, script, onClose: () {});
    expect(find.text('See who liked is coming soon.'), findsOneWidget);
    expect(find.byKey(const ValueKey('likers-close')), findsOneWidget);
  });

  testWidgets('accessRequired hands over to the upsell', (tester) async {
    var handedOver = 0;
    final script = ScriptedLikers([
      functionsError('failed-precondition', reason: 'likersAccessRequired'),
    ]);
    await pumpList(tester, script, onAccessRequired: () => handedOver++);
    expect(handedOver, 1);
  });

  testWidgets('a row opens the liker and keeps the list', (tester) async {
    Liker? opened;
    final script = ScriptedLikers([
      pageWire([likerWire('julia', 'Julia Nowak')]),
    ]);
    await pumpList(
      tester,
      script,
      onOpenLiker: (context, liker) async => opened = liker,
    );
    await tester.tap(find.text('Julia Nowak'));
    await settleAll(tester);
    expect(opened?.userId, 'julia');
    expect(find.text('Julia Nowak'), findsOneWidget);
  });

  testWidgets('long names ellipsize and keep the rosette at 320 px, 200 %', (
    tester,
  ) async {
    final script = ScriptedLikers([
      pageWire([
        likerWire('marta', 'Aleksandra Konstantynopolitańczykiewicz Marta'),
        likerWire('julia', 'Julia Nowak'),
      ], cursor: kTestCursor),
    ]);
    await pumpList(
      tester,
      script,
      total: 9,
      size: const Size(320, 700),
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(YoVipRosette), findsOneWidget);
    final rosette = tester.getRect(find.byType(YoVipRosette));
    expect(rosette.right, lessThanOrEqualTo(320));
    expect(find.byKey(const ValueKey('likers-load-more')), findsOneWidget);
  });

  testWidgets('RTL lays out without errors', (tester) async {
    final script = ScriptedLikers([
      pageWire([
        likerWire('marta', 'Marta Wiśniewska'),
        likerWire('julia', 'Julia Nowak'),
      ]),
    ]);
    await pumpList(tester, script, direction: TextDirection.rtl);
    expect(tester.takeException(), isNull);
    final avatarX = tester
        .getCenter(find.byKey(const ValueKey('likers-row-julia')))
        .dx;
    final heart = tester.getCenter(find.byIcon(Icons.favorite_rounded).last).dx;
    expect(heart, lessThan(avatarX));
  });
}
