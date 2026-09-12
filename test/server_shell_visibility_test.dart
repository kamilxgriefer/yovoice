// The gate items the servers shell round-2 review left open, each named for
// the failure it locks out rather than for the code path it walks.
//
//  * **B3 / F-1** — a joined conversation surviving a rail or dock switch
//    with the microphone still open and no indicator anywhere. The client
//    half (`ServersScreen.isVisible` → `ServerWorkspaceScreen.isVisible` →
//    leave) landed in the previous pass and is pinned by
//    `server_shell_fix_test.dart`; the HOST half — the Home shell publishing
//    that visibility for its retained content slot — did not exist, so the
//    defect was live in the product. The product's answer is that leaving the
//    surface leaves the conversation, so these tests assert the session ENDS:
//    the alternative (keeping it alive) would have to keep an indicator on
//    screen and a truthful mute, and neither exists for a server session.
//  * **F-2** — an inline-hosted workspace with no way out of its error,
//    loading or "server unavailable" states.
//  * **F-5** — a privacy control whose failure was swallowed, leaving a
//    control that looks live and does nothing.
//
// `MainShell` itself is not pumpable (it builds MessageService, RoomService,
// AuthService and FirebaseAuth.instance directly), which is exactly why the
// host half could go missing unnoticed. The net here is therefore three
// layers: the typed seam the shell hands the slot, a source guard over the
// un-pumpable shell state itself, and a behavioural test over a faithful
// reconstruction of the shell's retained-slot composition — the same
// "reproduce the composition rather than mount the shell" approach
// `desktop_shell_test.dart` already uses.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/home/presentation/widgets/more_sheet.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/presentation/screens/server_workspace_screen.dart';
import 'package:yovoice/features/servers/presentation/screens/servers_screen.dart';
import 'package:yovoice/shared/widgets/states/yo_empty_state.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';

import 'server_independent_qa_support.dart';
import 'server_test_support.dart';

/// The file's CODE, with comment lines dropped and every run of whitespace
/// flattened: a reformat must not turn a guard into a false alarm, and prose
/// about a mechanism must never be mistaken for the mechanism itself.
String _flattened(String path) => File(path)
    .readAsStringSync()
    .split('\n')
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n')
    .replaceAll(RegExp(r'\s+'), ' ');

const _mainShell = 'lib/features/home/presentation/screens/main_shell.dart';
const _moreSheet = 'lib/features/home/presentation/widgets/more_sheet.dart';

Finder get _stateBack => find.byKey(const ValueKey('server-state-back'));
Finder get _directoryCreate => find.byKey(const ValueKey('servers-create'));

/// The dock, wherever it is in the tree — including inside a retained slot
/// the shell has moved off screen. A dock that is merely offstage is exactly
/// the shape B3 describes, so nothing here may skip it.
Finder get _dockAnywhere =>
    find.byKey(const ValueKey('server-conversation-dock'), skipOffstage: false);

String _dockStatus(WidgetTester tester) =>
    tester.widget<Text>(qaDockStatus).data ?? '';

/// A faithful stand-in for the shell's retained content slots: a slot is
/// built on FIRST visit, cached for the rest of the session, and kept mounted
/// inside an `IndexedStack` when another destination is selected — which is
/// precisely why a hidden Servers slot can hold an open microphone. The
/// visibility notifier is flipped the way `_onDestinationSelected` flips it.
class _ShellSlots extends StatefulWidget {
  const _ShellSlots({required this.servers});

  /// Built once, with the shell's own notifier.
  final Widget Function(ValueListenable<bool> isVisible) servers;

  @override
  State<_ShellSlots> createState() => _ShellSlotsState();
}

class _ShellSlotsState extends State<_ShellSlots> {
  static const _serversSlot = 13;
  final ValueNotifier<bool> _serversVisible = ValueNotifier<bool>(false);
  final Map<int, Widget> _builtSlots = <int, Widget>{};
  int _selected = 0;

  @override
  void dispose() {
    _serversVisible.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (_selected == index) return;
    _builtSlots.putIfAbsent(
      index,
      () => index == _serversSlot
          ? widget.servers(_serversVisible)
          : const Center(child: Text('HOME')),
    );
    setState(() => _selected = index);
    _serversVisible.value = index == _serversSlot;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        Expanded(
          child: IndexedStack(
            index: _selected == _serversSlot ? 1 : 0,
            children: [
              _builtSlots[0] ?? const Center(child: Text('HOME')),
              _builtSlots[_serversSlot] ?? const SizedBox.shrink(),
            ],
          ),
        ),
        Row(
          children: [
            TextButton(
              key: const ValueKey('shell-home'),
              onPressed: () => _select(0),
              child: const Text('Start'),
            ),
            TextButton(
              key: const ValueKey('shell-servers'),
              onPressed: () => _select(_serversSlot),
              child: const Text('Serwery'),
            ),
          ],
        ),
      ],
    ),
  );
}

void main() {
  group('B3 — the Home shell publishes its Servers slot\'s visibility', () {
    // The typed half of this contract — that `moreDestinationScreen` really
    // does hand the listenable to `ServersScreen` — is asserted against the
    // compiler in `main_shell_servers_slot_test.dart`, the Home suite that
    // owns slot 13. What is left here is the half no type can express: that
    // the un-pumpable `MainShell` state owns the notifier and flips it on
    // every destination change.
    test('a Servers route pushed without one is unchanged', () {
      final screen =
          moreDestinationScreen(MoreDestination.servers) as ServersScreen;
      expect(
        screen.isVisible,
        isNull,
        reason: 'a pushed route ends its conversation by being popped; '
            'null must keep meaning always visible',
      );
      expect(screen.isRootTab, isFalse);
    });

    test('main_shell owns a Servers visibility notifier and drives it from '
        'the selected destination', () {
      final source = _flattened(_mainShell);
      expect(
        source,
        matches(RegExp(r'_serversVisible\s*=\s*ValueNotifier<bool>')),
        reason: 'the shell must own the notifier beside _momentsVisible — '
            'the slot is built once and cached, so a constructor argument '
            'could never be updated',
      );
      expect(
        source,
        matches(RegExp(r'serversVisible:\s*_serversVisible')),
        reason: 'the notifier has to reach the Servers slot through '
            'moreDestinationScreen, or the wiring stops at the shell',
      );
      expect(
        source,
        matches(
          RegExp(r'_serversVisible\.value\s*=\s*index\s*==\s*_serversSlot'),
        ),
        reason: 'selecting any other destination must publish false; this is '
            'the line that ends the conversation on a rail or dock switch',
      );
      expect(
        source,
        matches(RegExp(r'_serversVisible\.dispose\(\)')),
        reason: 'a notifier the shell owns is a notifier the shell disposes',
      );
      expect(
        source,
        isNot(contains('TickerMode.of(')),
        reason: 'TickerMode is flipped by ANY opaque route pushed over the '
            'shell (a profile, Settings, a moment detail), so it must never '
            'stand in for slot visibility — it would end a live conversation '
            'the person never left',
      );
    });

    test('more_sheet passes the listenable into ServersScreen, and only '
        'there', () {
      final source = _flattened(_moreSheet);
      expect(
        source,
        matches(
          RegExp(
            r'MoreDestination\.servers\s*=>\s*ServersScreen\('
            r'[\s\S]{0,160}?isVisible:\s*serversVisible',
          ),
        ),
        reason: 'the one Home call site for the servers feature is where the '
            'shell\'s visibility becomes the screen\'s',
      );
    });
  });

  group('B3 — a live conversation does not survive a destination switch', () {
    testWidgets('switching the shell to another destination ends the '
        'conversation, releases the device and removes the dock — while the '
        'slot itself stays retained', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()
        ..servers = [qaServer(ServerType.friends)]
        ..channels = qaChannels(ServerType.friends);
      final connector = FakeServerMediaConnector();
      await pumpServers(
        tester,
        _ShellSlots(
          servers: (visible) => ServersScreen(
            repository: repository,
            isRootTab: true,
            chatService: qaChat(),
            connector: connector,
            isVisible: visible,
          ),
        ),
        size: const Size(1440, 900),
      );

      await tester.tap(find.byKey(const ValueKey('shell-servers')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('server-directory-s')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('server-channel-lounge')));
      await tester.pumpAndSettle();
      final link = await qaJoinAndSettle(tester, connector, roster: qaRoster);

      // Joining never opens the microphone on its own; the person does.
      expect(link.microphoneCalls, isEmpty);
      await tester.tap(find.byKey(const ValueKey('server-dock-microphone')));
      await tester.pumpAndSettle();
      expect(link.microphoneCalls, [true]);
      expect(link.isMicrophoneEnabled, isTrue);
      expect(pumpedVoiceDevice.keepAliveStarts, 1);

      // The rail or dock moves to Start. The shell keeps the Servers slot
      // mounted, so nothing here is a dispose.
      await tester.tap(find.byKey(const ValueKey('shell-home')));
      await tester.pumpAndSettle();

      expect(
        find.byType(ServersScreen, skipOffstage: false),
        findsOneWidget,
        reason: 'the retained slot must still be mounted — otherwise this '
            'test proves a dispose, not the visibility contract',
      );
      expect(
        link.disconnects,
        1,
        reason: 'the microphone stayed open behind a hidden slot',
      );
      expect(link.isMicrophoneEnabled, isFalse);
      expect(
        _dockAnywhere,
        findsNothing,
        reason: 'a conversation with no surface has no dock; keeping one '
            'offstage is the defect, not the indicator',
      );
      expect(
        pumpedVoiceDevice.keepAliveStops,
        1,
        reason: 'the Android keep-alive outlived the conversation',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('coming back finds the directory, not a phantom conversation',
        (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()
        ..servers = [qaServer(ServerType.friends)]
        ..channels = qaChannels(ServerType.friends);
      final connector = FakeServerMediaConnector();
      await pumpServers(
        tester,
        _ShellSlots(
          servers: (visible) => ServersScreen(
            repository: repository,
            isRootTab: true,
            chatService: qaChat(),
            connector: connector,
            isVisible: visible,
          ),
        ),
        size: const Size(1440, 900),
      );
      await tester.tap(find.byKey(const ValueKey('shell-servers')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('server-directory-s')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('server-channel-lounge')));
      await tester.pumpAndSettle();
      final link = await qaJoinAndSettle(tester, connector, roster: qaRoster);

      await tester.tap(find.byKey(const ValueKey('shell-home')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('shell-servers')));
      await tester.pumpAndSettle();

      expect(link.disconnects, 1, reason: 'returning must not re-join');
      expect(connector.links, hasLength(1));
      expect(
        _dockAnywhere,
        findsNothing,
        reason: 'a dock back on screen without a join would be a session '
            'nobody asked for',
      );
      expect(
        qaJoin,
        findsOneWidget,
        reason: 'joining stays explicit: the way back in is the join control',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('F-2 — an inline workspace always has a way back to the directory',
      () {
    Future<void> openInline(
      WidgetTester tester,
      TestServerRepository repository, {
      bool settle = true,
    }) async {
      await pumpServers(
        tester,
        ServersScreen(
          repository: repository,
          isRootTab: true,
          chatService: qaChat(),
          connector: FakeServerMediaConnector(),
        ),
        size: const Size(1440, 900),
      );
      await tester.tap(find.byKey(const ValueKey('server-directory-s')));
      if (settle) {
        await tester.pumpAndSettle();
      } else {
        await tester.pump();
      }
    }

    TestServerRepository base() => TestServerRepository()
      ..servers = [qaServer(ServerType.friends)]
      ..channels = qaChannels(ServerType.friends);

    testWidgets('the error state', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = base()
        ..serverStream = Stream<Server?>.error(StateError('denied'));
      await openInline(tester, repository);

      expect(find.byType(YoErrorState), findsOneWidget);
      expect(
        _stateBack,
        findsOneWidget,
        reason: 'the panel and the phone header are drawn INSIDE the '
            'workspace, which this state replaces — without a way out here '
            'the retained slot is a dead end for the rest of the session',
      );
      await tester.tap(_stateBack);
      await tester.pumpAndSettle();
      expect(_directoryCreate, findsOneWidget);
      expect(find.byType(YoErrorState), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the loading state', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final pending = StreamController<Server?>();
      addTearDown(pending.close);
      final repository = base()..serverStream = pending.stream;
      await openInline(tester, repository, settle: false);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        _stateBack,
        findsOneWidget,
        reason: 'a read that never answers must not trap anyone',
      );
      await tester.tap(_stateBack);
      await tester.pump();
      expect(_directoryCreate, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the "server unavailable" state', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = base()..serverStream = Stream<Server?>.value(null);
      await openInline(tester, repository);

      expect(find.text('Serwer jest niedostępny'), findsOneWidget);
      expect(find.byType(YoEmptyState), findsOneWidget);
      expect(
        _stateBack,
        findsOneWidget,
        reason: 'the owner deleting the server, or membership being revoked, '
            'is exactly when the person needs the directory back',
      );
      await tester.tap(_stateBack);
      await tester.pumpAndSettle();
      expect(_directoryCreate, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('narrowed to the phone tier the same exit is there', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = base()..serverStream = Stream<Server?>.value(null);
      await openInline(tester, repository);
      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpAndSettle();

      expect(_stateBack, findsOneWidget);
      await tester.tap(_stateBack);
      await tester.pumpAndSettle();
      expect(_directoryCreate, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('pushed as a route the app bar still owns Back — no second '
        'control', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = base()
        ..serverStream = Stream<Server?>.error(StateError('denied'));
      await pumpServers(
        tester,
        ServerWorkspaceScreen(
          serverId: 's',
          repository: repository,
          chatService: qaChat(),
          connector: FakeServerMediaConnector(),
        ),
        size: const Size(390, 844),
      );

      expect(find.byType(AppBar), findsOneWidget);
      expect(
        _stateBack,
        findsNothing,
        reason: 'a pushed route carries a real app bar with Back; a second '
            'control would be chrome drawn twice',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('F-5 — a privacy control that fails says so', () {
    testWidgets('a mute the provider refuses is surfaced, and the control '
        'stays truthful', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()
        ..servers = [qaServer(ServerType.friends)]
        ..channels = qaChannels(ServerType.friends);
      final connector = FakeServerMediaConnector();
      await pumpServers(
        tester,
        qaWorkspace(repository, channelId: 'lounge', connector: connector),
        size: const Size(1440, 900),
      );
      final link = await qaJoinAndSettle(tester, connector, roster: qaRoster);
      expect(_dockStatus(tester), 'połączono');

      // Exactly what the production link raises when the session is gone or
      // the local participant has been released — the reconnect window B4
      // deliberately opened this control during.
      link.failMicrophoneWith = StateError(
        'The media session is not connected.',
      );
      await tester.tap(find.byKey(const ValueKey('server-dock-microphone')));
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: 'the rejected future was never caught, so the failure '
            'escaped into the zone instead of reaching the person',
      );
      expect(
        _dockStatus(tester),
        'Nie udało się zmienić ustawienia dźwięku.',
        reason: 'a control that looks live and silently does nothing is the '
            'shape the contract forbids',
      );
      expect(
        link.isMicrophoneEnabled,
        isFalse,
        reason: 'the capture never opened, so the control must not claim it '
            'did',
      );
      expect(
        find.byKey(const ValueKey('server-dock-microphone')),
        findsOneWidget,
      );

      // The next attempt clears the message and works.
      await tester.tap(find.byKey(const ValueKey('server-dock-microphone')));
      await tester.pumpAndSettle();
      expect(link.isMicrophoneEnabled, isTrue);
      expect(_dockStatus(tester), 'połączono');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a headphones press that fails is surfaced the same way', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()
        ..servers = [qaServer(ServerType.friends)]
        ..channels = qaChannels(ServerType.friends);
      final connector = FakeServerMediaConnector();
      await pumpServers(
        tester,
        qaWorkspace(repository, channelId: 'lounge', connector: connector),
        size: const Size(1440, 900),
      );
      final link = await qaJoinAndSettle(tester, connector, roster: qaRoster);
      link.failDeafenWith = StateError('The media session is not connected.');
      await tester.tap(find.byKey(const ValueKey('server-dock-headphones')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(_dockStatus(tester), 'Nie udało się zmienić ustawienia dźwięku.');
      expect(link.isDeafened, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('leaving clears the message with the conversation', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()
        ..servers = [qaServer(ServerType.friends)]
        ..channels = qaChannels(ServerType.friends);
      final connector = FakeServerMediaConnector();
      await pumpServers(
        tester,
        qaWorkspace(repository, channelId: 'lounge', connector: connector),
        size: const Size(1440, 900),
      );
      final link = await qaJoinAndSettle(tester, connector, roster: qaRoster);
      link.failMicrophoneWith = StateError('gone');
      await tester.tap(find.byKey(const ValueKey('server-dock-microphone')));
      await tester.pumpAndSettle();
      expect(_dockStatus(tester), 'Nie udało się zmienić ustawienia dźwięku.');

      await tester.tap(qaLeave);
      await tester.pumpAndSettle();
      expect(qaDock, findsNothing);
      expect(qaJoin, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
