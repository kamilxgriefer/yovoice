// Developer-only harness for the "New message" bottom sheet.
//
// Reaching that sheet in the real app needs a signed-in Firebase session and
// real friend/conversation data, which makes the loading, empty, no-results
// and error states impractical to inspect by hand — especially on Flutter
// Web, where the reported "large light-grey panel" bug was observed.
//
// This entry point renders the real [NewMessageSheet] with the real
// [AppTheme.darkTheme] and the same showModalBottomSheet invocation the app
// uses, but with streams we control.
//
// Run with:
//   flutter run -d chrome -t lib/dev/new_message_preview.dart
//
// Not referenced by lib/main.dart and therefore not part of any shipped
// build.

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_immersive_colors.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/firebase_options.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/presentation/screens/messages_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The generated web plugin registrant registers every Firebase plugin at
  // startup regardless of entry point. Initialising the app keeps those
  // registrations happy, but this preview must render even when Firebase is
  // unreachable (no App Check token, unauthorised host, offline) — the
  // sheet is driven entirely by the local streams below.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 5));
  } catch (error) {
    debugPrint('Preview: continuing without Firebase ($error)');
  }
  runApp(const _PreviewApp());
}

const String _me = 'me';

enum PreviewState { loading, results, noFriends, noSearchResults, error }

Conversation _conversation(String id, String name) {
  return Conversation(
    id: id,
    participantIds: [_me, id],
    participantNames: {_me: 'Me', id: name},
    participantEmails: {_me: 'me@yovoice.app', id: '$id@yovoice.app'},
    participantPhotoUrls: const {},
    unreadCounts: const {},
    lastMessage: 'Hey, are you joining the room later?',
    lastMessageType: MessageType.text,
    lastMessageSenderId: id,
    updatedAt: DateTime.now(),
    createdAt: DateTime.now(),
    archivedBy: const [],
    mutedBy: const [],
  );
}

FriendUser _friend(String id, String name, {bool online = false}) {
  return FriendUser(
    id: id,
    displayName: name,
    email: '$id@yovoice.app',
    photoUrl: null,
    isOnline: online,
    lastSeen: DateTime.now(),
  );
}

class _PreviewApp extends StatefulWidget {
  const _PreviewApp();

  @override
  State<_PreviewApp> createState() => _PreviewAppState();
}

class _PreviewAppState extends State<_PreviewApp> {
  PreviewState _state = PreviewState.results;

  /// Toggle to compare the pre-fix single-subscription streams against the
  /// shipped broadcast+replay ones.
  bool _legacyStreams = false;

  // Rebuilt whenever the selected state changes. Held as fields (not
  // getters) so that, exactly like MessagesScreen, ONE stream instance is
  // shared between the background list and the sheet — which is what
  // surfaces the "already listened to" bug.
  late Stream<List<FriendUser>> _friends;
  late Stream<List<Conversation>> _conversations;

  @override
  void initState() {
    super.initState();
    _rebuildStreams();
  }

  /// Mirrors `FriendService.watchFriends()`.
  ///
  /// Set [legacy] to true to get the pre-fix shape — a *single-subscription*
  /// controller, which reproduces "Bad state: Stream has already been
  /// listened to" as soon as the sheet becomes the second listener. False
  /// uses the shipped shape: broadcast + last-value replay via Stream.multi.
  Stream<List<T>> _serviceLikeStream<T>(List<T> value, {bool legacy = false}) {
    final controller = legacy
        ? StreamController<List<T>>()
        : StreamController<List<T>>.broadcast();
    List<T>? latest;

    controller.onListen = () {
      switch (_state) {
        case PreviewState.loading:
          break; // never emits -> ConnectionState.waiting
        case PreviewState.error:
          controller.addError(Exception('permission-denied'));
        case PreviewState.noFriends:
        case PreviewState.noSearchResults:
        case PreviewState.results:
          latest = value;
          controller.add(value);
      }
    };

    if (legacy) return controller.stream;

    return Stream<List<T>>.multi((subscriber) {
      final cached = latest;
      if (cached != null) subscriber.add(cached);
      final subscription = controller.stream.listen(
        subscriber.add,
        onError: subscriber.addError,
        onDone: subscriber.close,
      );
      subscriber.onCancel = subscription.cancel;
    });
  }

  void _rebuildStreams() {
    final friends = switch (_state) {
      PreviewState.noFriends => <FriendUser>[],
      _ => [
        _friend('ava', 'Ava Stone', online: true),
        _friend('ben', 'Ben Carter'),
        _friend('cleo', 'Cleo Nakamura', online: true),
      ],
    };
    final conversations = switch (_state) {
      PreviewState.noFriends => <Conversation>[],
      _ => [_conversation('ava', 'Ava Stone')],
    };
    _friends = _serviceLikeStream(friends, legacy: _legacyStreams);
    _conversations = _serviceLikeStream(conversations, legacy: _legacyStreams);
  }

  Future<void> _open(BuildContext context) async {
    await showNewMessageSheet(
      context,
      friendsStream: _friends,
      conversationsStream: _conversations,
      currentUserId: _me,
      onFriendSelected: (_) {},
      onConversationSelected: (_) {},
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: Builder(
        builder: (context) => Scaffold(
          backgroundColor: AppImmersiveColors.background,
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'New message sheet preview',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final state in PreviewState.values)
                      ChoiceChip(
                        label: Text(state.name),
                        selected: _state == state,
                        onSelected: (_) => setState(() {
                          _state = state;
                          _rebuildStreams();
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  value: _legacyStreams,
                  onChanged: (value) => setState(() {
                    _legacyStreams = value;
                    _rebuildStreams();
                  }),
                  title: const Text(
                    'Use pre-fix single-subscription streams',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 8),
                // Stands in for _FriendsRow on MessagesScreen: the FIRST
                // subscriber to the shared friends stream. The sheet then
                // becomes the second one.
                StreamBuilder<List<FriendUser>>(
                  stream: _friends,
                  builder: (context, snapshot) => Text(
                    'background listener: ${snapshot.data?.length ?? 0} friends',
                    style: const TextStyle(color: Colors.white54),
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: () => _open(context),
                  child: const Text('Open sheet'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
