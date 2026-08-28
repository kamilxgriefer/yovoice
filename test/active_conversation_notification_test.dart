import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/calls/presentation/direct_call_route_registry.dart';
import 'package:yovoice/features/home/presentation/screens/main_shell.dart';
import 'package:yovoice/features/messages/data/services/active_conversation_registry.dart';
import 'package:yovoice/features/notifications/data/models/app_notification.dart';
import 'package:yovoice/features/notifications/data/services/push_notification_service.dart';

void main() {
  late ActiveConversationRegistry activeConversations;

  setUp(() {
    activeConversations = ActiveConversationRegistry();
    DirectCallAlertRegistry.clear();
  });

  tearDown(DirectCallAlertRegistry.resetTestingConfiguration);

  test('reference counts survive overlapping route transitions', () {
    activeConversations
      ..enter('conversation-1')
      ..enter('conversation-1');

    activeConversations.leave('conversation-1');
    expect(activeConversations.contains('conversation-1'), isTrue);

    activeConversations.leave('conversation-1');
    expect(activeConversations.contains('conversation-1'), isFalse);
  });

  test('an open DM suppresses only its foreground message presentation', () {
    activeConversations.enter('conversation-1');
    var presentations = 0;

    bool present(NotificationType type, String targetId) {
      if (shouldSuppressForegroundNotification(
        type: type,
        targetId: targetId,
        activeConversations: activeConversations,
      )) {
        return false;
      }
      presentations++;
      return true;
    }

    expect(present(NotificationType.directMessage, 'conversation-1'), isFalse);
    expect(present(NotificationType.reply, 'conversation-1'), isFalse);
    expect(present(NotificationType.directMessage, 'conversation-2'), isTrue);
    expect(present(NotificationType.follow, 'conversation-1'), isTrue);
    expect(
      presentations,
      2,
      reason: 'suppressed events never reach native/local sound or banner UI',
    );
  });

  test('foreground direct-call push remains eligible as listener fallback', () {
    expect(
      shouldSuppressForegroundNotification(
        type: NotificationType.directCall,
        targetId: 'call-1',
        activeConversations: activeConversations,
      ),
      isFalse,
    );
  });

  test('call alert falls back without allowing two owners', () async {
    final push = DirectCallAlertRegistry.claim(
      'call-1',
      DirectCallAlertOwner.push,
    );
    final coordinatorWhilePushOwns = DirectCallAlertRegistry.claim(
      'call-1',
      DirectCallAlertOwner.coordinator,
    );

    expect(push.ownsAlert, isTrue);
    expect(coordinatorWhilePushOwns.ownsAlert, isFalse);

    DirectCallAlertRegistry.complete(push, presented: false);
    expect(await coordinatorWhilePushOwns.result, isFalse);

    final coordinatorFallback = DirectCallAlertRegistry.claim(
      'call-1',
      DirectCallAlertOwner.coordinator,
    );
    expect(coordinatorFallback.ownsAlert, isTrue);
    DirectCallAlertRegistry.complete(coordinatorFallback, presented: true);

    final latePush = DirectCallAlertRegistry.claim(
      'call-1',
      DirectCallAlertOwner.push,
    );
    expect(latePush.ownsAlert, isFalse);
    expect(await latePush.result, isTrue);
  });

  test('push can take over when coordinator audio fails', () async {
    final coordinator = DirectCallAlertRegistry.claim(
      'call-2',
      DirectCallAlertOwner.coordinator,
    );
    final waitingPush = DirectCallAlertRegistry.claim(
      'call-2',
      DirectCallAlertOwner.push,
    );
    expect(coordinator.ownsAlert, isTrue);
    expect(waitingPush.ownsAlert, isFalse);

    DirectCallAlertRegistry.complete(coordinator, presented: false);
    expect(await waitingPush.result, isFalse);

    final pushFallback = DirectCallAlertRegistry.claim(
      'call-2',
      DirectCallAlertOwner.push,
    );
    expect(pushFallback.ownsAlert, isTrue);
    DirectCallAlertRegistry.complete(pushFallback, presented: true);
    expect(await pushFallback.result, isTrue);
  });

  test(
    'completed alert suppresses late duplicates until retention expires',
    () async {
      var now = DateTime(2026, 8, 28, 12);
      DirectCallAlertRegistry.configureForTesting(clock: () => now);
      final original = DirectCallAlertRegistry.claim(
        'retained-call',
        DirectCallAlertOwner.coordinator,
      );
      DirectCallAlertRegistry.complete(original, presented: true);

      now = now.add(const Duration(minutes: 4));
      final lateDuplicate = DirectCallAlertRegistry.claim(
        'retained-call',
        DirectCallAlertOwner.push,
      );
      expect(lateDuplicate.ownsAlert, isFalse);
      expect(await lateDuplicate.result, isTrue);

      now = now.add(const Duration(minutes: 2));
      final afterRetention = DirectCallAlertRegistry.claim(
        'retained-call',
        DirectCallAlertOwner.push,
      );
      expect(afterRetention.ownsAlert, isTrue);
    },
  );

  test(
    'registry stays bounded and preserves the newest duplicate guards',
    () async {
      var now = DateTime(2026, 8, 28, 13);
      DirectCallAlertRegistry.configureForTesting(
        clock: () => now,
        maximumEntries: 3,
      );
      for (final callId in <String>['call-a', 'call-b', 'call-c', 'call-d']) {
        final claim = DirectCallAlertRegistry.claim(
          callId,
          DirectCallAlertOwner.coordinator,
        );
        DirectCallAlertRegistry.complete(claim, presented: true);
        now = now.add(const Duration(seconds: 1));
      }

      expect(DirectCallAlertRegistry.debugEntryCount, 3);
      final recentDuplicate = DirectCallAlertRegistry.claim(
        'call-d',
        DirectCallAlertOwner.push,
      );
      expect(recentDuplicate.ownsAlert, isFalse);
      expect(await recentDuplicate.result, isTrue);

      final evictedOldest = DirectCallAlertRegistry.claim(
        'call-a',
        DirectCallAlertOwner.push,
      );
      expect(evictedOldest.ownsAlert, isTrue);
      expect(DirectCallAlertRegistry.debugEntryCount, 3);
    },
  );

  test('an abandoned active alert is pruned and releases its waiter', () async {
    var now = DateTime(2026, 8, 28, 14);
    DirectCallAlertRegistry.configureForTesting(
      clock: () => now,
      activeClaimTimeout: const Duration(seconds: 30),
    );
    final abandonedOwner = DirectCallAlertRegistry.claim(
      'abandoned-call',
      DirectCallAlertOwner.coordinator,
    );
    final waiter = DirectCallAlertRegistry.claim(
      'abandoned-call',
      DirectCallAlertOwner.push,
    );

    now = now.add(const Duration(seconds: 31));
    final replacement = DirectCallAlertRegistry.claim(
      'abandoned-call',
      DirectCallAlertOwner.coordinator,
    );
    expect(await waiter.result, isFalse);
    expect(replacement.ownsAlert, isTrue);
    expect(DirectCallAlertRegistry.debugEntryCount, 1);

    // The evicted owner's delayed callback must not settle a replacement
    // owned later by the same delivery path.
    DirectCallAlertRegistry.complete(abandonedOwner, presented: true);
    final replacementWaiter = DirectCallAlertRegistry.claim(
      'abandoned-call',
      DirectCallAlertOwner.push,
    );
    DirectCallAlertRegistry.complete(replacement, presented: false);
    expect(await replacementWaiter.result, isFalse);
  });

  test(
    'shell unread overlay also respects a chat opened outside Chats tab',
    () {
      activeConversations.enter('conversation-1');

      expect(
        shouldPresentIncomingMessageOverlay(
          selectedIndex: 0,
          conversationId: 'conversation-1',
          activeConversations: activeConversations,
        ),
        isFalse,
      );
      expect(
        shouldPresentIncomingMessageOverlay(
          selectedIndex: 0,
          conversationId: 'conversation-2',
          activeConversations: activeConversations,
        ),
        isTrue,
      );
      expect(
        shouldPresentIncomingMessageOverlay(
          selectedIndex: 1,
          conversationId: 'conversation-2',
          activeConversations: activeConversations,
        ),
        isFalse,
      );
    },
  );
}
