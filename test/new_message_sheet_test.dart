import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/presentation/screens/messages_screen.dart';

const String _me = 'me';

FriendUser _friend(String id, String name) => FriendUser(
  id: id,
  displayName: name,
  email: '$id@yovoice.app',
  photoUrl: null,
  isOnline: false,
  lastSeen: null,
);

Conversation _conversation(String id, String name) => Conversation(
  id: id,
  participantIds: [_me, id],
  participantNames: {_me: 'Me', id: name},
  participantEmails: {_me: 'me@yovoice.app', id: '$id@yovoice.app'},
  participantPhotoUrls: const {},
  unreadCounts: const {},
  lastMessage: 'Hey there',
  lastMessageType: MessageType.text,
  lastMessageSenderId: id,
  updatedAt: DateTime(2026, 8, 8),
  createdAt: DateTime(2026, 8, 1),
  archivedBy: const [],
  mutedBy: const [],
);

/// Pumps the sheet the same way `MessagesScreen` does: the streams are
/// created once and are ALREADY being listened to by another widget before
/// the sheet mounts. That second subscription is what used to blow up.
Future<void> _pumpSheet(
  WidgetTester tester, {
  required Stream<List<FriendUser>> friends,
  required Stream<List<Conversation>> conversations,
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.darkTheme,
      home: Scaffold(
        body: Column(
          children: [
            // Stands in for _FriendsRow: the first subscriber.
            StreamBuilder<List<FriendUser>>(
              stream: friends,
              builder: (context, snapshot) =>
                  Text('friends: ${snapshot.data?.length ?? 0}'),
            ),
            Expanded(
              child: NewMessageSheet(
                friendsStream: friends,
                conversationsStream: conversations,
                currentUserId: _me,
                onFriendSelected: (_) {},
                onConversationSelected: (_) {},
              ),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<FocusNode> _openProductionRoute(
  WidgetTester tester, {
  required Size size,
  TextScaler textScaler = TextScaler.noScaling,
  EdgeInsets safeArea = EdgeInsets.zero,
  ThemeData? theme,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final launcherFocus = FocusNode(debugLabel: 'new-message-launcher');
  addTearDown(launcherFocus.dispose);
  final friends = Stream<List<FriendUser>>.value([
    _friend('ava', 'Ava Stone'),
    _friend('ben', 'Ben Carter'),
  ]).asBroadcastStream();
  final conversations = Stream<List<Conversation>>.value([
    _conversation('cleo', 'Cleo Nakamura'),
  ]).asBroadcastStream();

  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.darkTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: textScaler,
          padding: safeArea,
          viewPadding: safeArea,
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              focusNode: launcherFocus,
              onPressed: () {
                unawaited(
                  showNewMessageSheet(
                    context,
                    friendsStream: friends,
                    conversationsStream: conversations,
                    currentUserId: _me,
                    onFriendSelected: (_) {},
                    onConversationSelected: (_) {},
                  ),
                );
              },
              child: const Text('Open new message'),
            ),
          ),
        ),
      ),
    ),
  );

  launcherFocus.requestFocus();
  await tester.pump();
  await tester.tap(find.text('Open new message'));
  await tester.pumpAndSettle();
  return launcherFocus;
}

void main() {
  group('NewMessageSheet', () {
    testWidgets('survives a second subscription to the shared friends stream', (
      tester,
    ) async {
      // Regression test for the "huge light-grey panel" bug: FriendService
      // .watchFriends() handed back a single-subscription stream, so the
      // sheet's StreamBuilder threw "Stream has already been listened to"
      // and Flutter swapped the whole content area for a bare grey
      // ErrorWidget (invisible as an error in release web builds).
      final friendService = _FakeFriendsSource([
        _friend('ava', 'Ava Stone'),
        _friend('ben', 'Ben Carter'),
      ]);
      addTearDown(friendService.dispose);

      await _pumpSheet(
        tester,
        friends: friendService.stream,
        conversations: Stream<List<Conversation>>.value([
          _conversation('ava', 'Ava Stone'),
        ]).asBroadcastStream(),
      );
      await tester.pump(const Duration(milliseconds: 10));

      expect(tester.takeException(), isNull);
      expect(find.byType(ErrorWidget), findsNothing);
    });

    testWidgets('renders friends and recent conversations', (tester) async {
      final friendService = _FakeFriendsSource([
        _friend('ava', 'Ava Stone'),
        _friend('ben', 'Ben Carter'),
      ]);
      addTearDown(friendService.dispose);

      await _pumpSheet(
        tester,
        friends: friendService.stream,
        conversations: Stream<List<Conversation>>.value([
          _conversation('cleo', 'Cleo Nakamura'),
        ]).asBroadcastStream(),
      );
      await tester.pump(const Duration(milliseconds: 10));

      expect(find.text('New message'), findsOneWidget);
      expect(find.text('Ava Stone'), findsOneWidget);
      expect(find.text('Cleo Nakamura'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the themed empty state when there are no friends', (
      tester,
    ) async {
      final friendService = _FakeFriendsSource(const []);
      addTearDown(friendService.dispose);

      await _pumpSheet(
        tester,
        friends: friendService.stream,
        conversations: Stream<List<Conversation>>.value(
          const [],
        ).asBroadcastStream(),
      );
      await tester.pump(const Duration(milliseconds: 10));

      expect(find.text('Add friends to start messaging them here.'), findsOne);
      expect(find.byType(ErrorWidget), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('stays on the themed surface when the friends stream errors', (
      tester,
    ) async {
      final friendService = _FakeFriendsSource(
        const [],
        error: Exception('permission-denied'),
      );
      addTearDown(friendService.dispose);

      await _pumpSheet(
        tester,
        friends: friendService.stream,
        conversations: Stream<List<Conversation>>.error(
          Exception('permission-denied'),
        ).asBroadcastStream(),
      );
      await tester.pump(const Duration(milliseconds: 10));

      // A stream error must not produce Flutter's grey ErrorWidget, and it
      // must not be mistaken for "you have no friends".
      expect(find.byType(ErrorWidget), findsNothing);
      expect(find.text("We couldn't load your people"), findsOne);
      expect(
        find.text('Add friends to start messaging them here.'),
        findsNothing,
      );
    });

    for (final entry in <String, ThemeData>{
      'dark': AppTheme.darkTheme,
      'light': AppTheme.lightTheme,
    }.entries) {
      testWidgets('owns its ${entry.key} semantic Material surface', (
        tester,
      ) async {
        // The sheet must paint its own Material: showModalBottomSheet is
        // transparent, and ListTile ink resolves against this exact surface.
        final friendService = _FakeFriendsSource([_friend('ava', 'Ava Stone')]);
        addTearDown(friendService.dispose);

        await _pumpSheet(
          tester,
          friends: friendService.stream,
          conversations: Stream<List<Conversation>>.value(
            const [],
          ).asBroadcastStream(),
          theme: entry.value,
        );
        await tester.pump(const Duration(milliseconds: 10));

        final palette = entry.value.extension<AppPalette>()!;
        final surface = tester.widget<Material>(
          find.byKey(const ValueKey('new-message-sheet-surface')),
        );
        expect(surface.color, palette.surfaceRaised);
        final title = tester.widget<Text>(find.text('New message'));
        expect(title.style?.color, palette.textPrimary);
      });
    }

    testWidgets('light empty and error states remain product UI', (
      tester,
    ) async {
      final emptySource = _FakeFriendsSource(const []);
      addTearDown(emptySource.dispose);
      await _pumpSheet(
        tester,
        friends: emptySource.stream,
        conversations: Stream<List<Conversation>>.value(
          const [],
        ).asBroadcastStream(),
        theme: AppTheme.lightTheme,
      );
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.text('Add friends to start messaging them here.'), findsOne);
      expect(find.byType(ErrorWidget), findsNothing);

      final errorSource = _FakeFriendsSource(
        const [],
        error: Exception('permission-denied'),
      );
      addTearDown(errorSource.dispose);
      await _pumpSheet(
        tester,
        friends: errorSource.stream,
        conversations: Stream<List<Conversation>>.error(
          Exception('permission-denied'),
        ).asBroadcastStream(),
        theme: AppTheme.lightTheme,
      );
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.text("We couldn't load your people"), findsOne);
      expect(find.byType(ErrorWidget), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('production New message route', () {
    testWidgets('mobile has one handle attached to the visible surface', (
      tester,
    ) async {
      await _openProductionRoute(tester, size: const Size(390, 844));

      final handle = find.byKey(const ValueKey('modal-sheet-drag-handle'));
      expect(handle, findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString() == '_DragHandle',
        ),
        findsNothing,
      );
      expect(find.byType(NewMessageSheet), findsOneWidget);

      final surface = find
          .descendant(
            of: find.byType(NewMessageSheet),
            matching: find.byType(Material),
          )
          .first;
      expect(
        tester.getTopLeft(handle).dy - tester.getTopLeft(surface).dy,
        inInclusiveRange(0, 48),
      );
      expect(tester.getTopLeft(handle).dy, greaterThan(100));
    });

    testWidgets('desktop has no drag cue and keeps one 44px Close', (
      tester,
    ) async {
      await _openProductionRoute(tester, size: const Size(1440, 900));

      expect(
        find.byKey(const ValueKey('modal-sheet-drag-handle')),
        findsNothing,
      );
      final close = find.bySemanticsLabel('Close New message');
      expect(close, findsOneWidget);
      final closeSize = tester.getSize(close);
      expect(closeSize.width, greaterThanOrEqualTo(44));
      expect(closeSize.height, greaterThanOrEqualTo(44));
      expect(find.bySemanticsLabel('New message'), findsWidgets);
    });

    testWidgets('Close and Escape dismiss one route and restore focus', (
      tester,
    ) async {
      var launcherFocus = await _openProductionRoute(
        tester,
        size: const Size(390, 844),
      );
      expect(find.byType(NewMessageSheet), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Close New message'));
      await tester.pumpAndSettle();
      expect(find.byType(NewMessageSheet), findsNothing);
      expect(launcherFocus.hasFocus, isTrue);

      launcherFocus = await _openProductionRoute(
        tester,
        size: const Size(390, 844),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(NewMessageSheet), findsNothing);
      expect(launcherFocus.hasFocus, isTrue);
    });

    testWidgets('scrim and swipe dismiss the top route', (tester) async {
      await _openProductionRoute(tester, size: const Size(390, 844));
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(find.byType(NewMessageSheet), findsNothing);

      await _openProductionRoute(tester, size: const Size(390, 844));
      final sheetTop = tester.getTopLeft(find.byType(NewMessageSheet)).dy;
      await tester.dragFrom(Offset(80, sheetTop + 24), const Offset(0, 700));
      await tester.pumpAndSettle();
      expect(find.byType(NewMessageSheet), findsNothing);
    });

    testWidgets('expanded sheet keeps Close below the phone top safe area', (
      tester,
    ) async {
      const topInset = 59.0;
      await _openProductionRoute(
        tester,
        size: const Size(390, 844),
        safeArea: const EdgeInsets.only(top: topInset),
      );

      final sheetTop = tester.getTopLeft(find.byType(NewMessageSheet)).dy;
      await tester.dragFrom(Offset(80, sheetTop + 24), const Offset(0, -700));
      await tester.pumpAndSettle();

      final close = find.bySemanticsLabel('Close New message');
      expect(tester.getTopLeft(close).dy, greaterThanOrEqualTo(topInset));
      expect(tester.takeException(), isNull);
    });

    for (final size in const <Size>[
      Size(320, 640),
      Size(390, 844),
      Size(430, 900),
      Size(768, 900),
      Size(1100, 900),
      Size(1440, 900),
      Size(2560, 1440),
    ]) {
      testWidgets('200% text stays usable at ${size.width.toInt()}px', (
        tester,
      ) async {
        await _openProductionRoute(
          tester,
          size: size,
          textScaler: const TextScaler.linear(2),
        );

        final close = find.bySemanticsLabel('Close New message');
        expect(close, findsOneWidget);
        final rect = tester.getRect(close);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(size.width));
        expect(rect.bottom, lessThanOrEqualTo(size.height));
        expect(tester.takeException(), isNull);
      });
    }

    for (final width in const <double>[320, 768]) {
      testWidgets('light theme stays usable at ${width.toInt()}px / 200%', (
        tester,
      ) async {
        await _openProductionRoute(
          tester,
          size: Size(width, 900),
          textScaler: const TextScaler.linear(2),
          theme: AppTheme.lightTheme,
        );

        final palette = AppTheme.lightTheme.extension<AppPalette>()!;
        final surface = tester.widget<Material>(
          find.byKey(const ValueKey('new-message-sheet-surface')),
        );
        expect(surface.color, palette.surfaceRaised);
        expect(find.bySemanticsLabel('Close New message'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}

/// Mirrors the shape of `FriendService.watchFriends()` — a controller with
/// onListen/onCancel lifecycle whose stream gets handed to more than one
/// widget.
class _FakeFriendsSource {
  _FakeFriendsSource(this._friends, {Object? error}) : _error = error {
    _controller = StreamController<List<FriendUser>>.broadcast();
    _controller.onListen = _emit;
  }

  final List<FriendUser> _friends;
  final Object? _error;
  late final StreamController<List<FriendUser>> _controller;
  List<FriendUser>? _latest;

  void _emit() {
    if (_controller.isClosed) return;
    if (_error != null) {
      _controller.addError(_error);
      return;
    }
    _latest = _friends;
    _controller.add(_friends);
  }

  /// Replays the last value to late subscribers, the same contract the real
  /// service now provides.
  Stream<List<FriendUser>> get stream =>
      Stream<List<FriendUser>>.multi((subscriber) {
        final cached = _latest;
        if (cached != null) subscriber.add(cached);
        final subscription = _controller.stream.listen(
          subscriber.add,
          onError: subscriber.addError,
          onDone: subscriber.close,
        );
        subscriber.onCancel = subscription.cancel;
      });

  void dispose() => _controller.close();
}
