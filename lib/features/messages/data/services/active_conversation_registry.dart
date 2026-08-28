import 'package:flutter/foundation.dart';

/// Process-local visibility registry for direct conversations.
///
/// A conversation can be mounted more than once during a route transition, so
/// this uses reference counts instead of a single nullable id. It deliberately
/// has no persistence: background/terminated push must remain enabled, while
/// only foreground surfaces consult this registry.
class ActiveConversationRegistry {
  ActiveConversationRegistry();

  static final ActiveConversationRegistry instance =
      ActiveConversationRegistry();

  final Map<String, int> _references = <String, int>{};

  void enter(String conversationId) {
    if (conversationId.isEmpty) return;
    _references.update(conversationId, (count) => count + 1, ifAbsent: () => 1);
  }

  void leave(String conversationId) {
    final count = _references[conversationId];
    if (count == null) return;
    if (count <= 1) {
      _references.remove(conversationId);
    } else {
      _references[conversationId] = count - 1;
    }
  }

  bool contains(String? conversationId) =>
      conversationId != null && _references.containsKey(conversationId);

  @visibleForTesting
  void clear() => _references.clear();
}
