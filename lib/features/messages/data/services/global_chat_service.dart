import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:yovoice/features/messages/data/models/global_message.dart';

/// Why a send is currently refused, so the composer can say which limit
/// was reached rather than "permission denied".
enum GlobalSendBlock { cooldown, hourlyLimit }

/// Whether this account may send right now, and if not, for how long.
class GlobalSendAllowance {
  const GlobalSendAllowance.allowed()
    : canSend = true,
      retryAfter = Duration.zero,
      reason = null;

  const GlobalSendAllowance.blocked({
    required this.retryAfter,
    required this.reason,
  }) : canSend = false;

  final bool canSend;
  final Duration retryAfter;
  final GlobalSendBlock? reason;
}

/// One snapshot of the Global Chat window: the messages themselves plus
/// the two facts the UI cannot otherwise know — whether older history
/// exists beyond the current window, and whether Firestore is currently
/// serving from its offline cache.
class GlobalChatFeed {
  const GlobalChatFeed({
    required this.messages,
    required this.hasMore,
    required this.isFromCache,
  });

  final List<GlobalMessage> messages;
  final bool hasMore;
  final bool isFromCache;
}

/// The community-wide Global Chat.
///
/// CANONICAL PATH: `globalChat/main/messages/{messageId}` — one channel,
/// shared by every authenticated account. The id `main` is pinned by
/// firestore.rules, so nobody can stand up a second "global" channel and
/// pass it off as this one. It is a separate top-level collection from
/// `conversations` (private DMs) and from `clubs/*/channels/*`
/// (member-only), so a public message can never be read, written or
/// counted by the private-message code paths.
///
/// SENDS ARE DIRECT, RULES-ENFORCED WRITES, not a Cloud Function — see
/// docs/Decisions.md ADR-013 and ADR-037. Every guarantee a callable
/// would give is expressed in rules instead: `senderId` must equal the
/// authenticated uid, `sentAt` must equal the server's `request.time`,
/// the denormalised name/avatar/creator flag must match the sender's real
/// profile document, the staff flag must match the ID token's role claim,
/// content must be non-blank after trimming and at most
/// [maxMessageLength] characters, and the write must be accompanied by
/// the cooldown document below.
///
/// RATE LIMIT: each send is a two-document batch — the message, plus the
/// sender's state at `globalChat/main/senders/{uid}`. Rules reject the
/// message unless that document, *after the same commit*, carries this
/// request's server time and this message's id, and reject the state
/// document itself unless BOTH limits allow it:
///
///  - [sendCooldown] since the previous message, and
///  - fewer than [fixedWindowLimit] messages inside the current
///    [fixedWindow] (a fixed, tumbling hour — see the constant).
///
/// A commit can only leave that document in one state, so batching a
/// hundred messages satisfies the check for at most one of them. Every
/// comparison is against the server's clock; the client never supplies
/// a timestamp.
class GlobalChatService {
  GlobalChatService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  /// The one public channel.
  static const String channelId = 'main';

  /// Mirrors the `content.size() <= 500` bound in firestore.rules. The
  /// composer enforces the same number so a rejection is a bug, not a
  /// routine outcome.
  static const int maxMessageLength = 500;

  /// Mirrors `duration.value(3, 's')` in firestore.rules.
  static const Duration sendCooldown = Duration(seconds: 3);

  /// Mirrors `duration.value(1, 'h')` and the `<= 200` cap in
  /// firestore.rules. The 3s floor alone would still permit 1,200
  /// messages an hour from one valid account; this is the sustained
  /// ceiling on top of it. 200/h is ~3.3 a minute held for a solid hour
  /// — well past real conversation, well short of useful spam volume.
  ///
  /// FIXED (tumbling) window, not rolling: `windowStartAt` is pinned at
  /// the first message of a window and only resets once a full hour has
  /// passed from that instant. Straddling a boundary therefore allows up
  /// to 400 messages across two adjacent hours — accepted, because it is
  /// still a 3x reduction and needs one document instead of per-message
  /// bookkeeping.
  static const Duration fixedWindow = Duration(hours: 1);
  static const int fixedWindowLimit = 200;

  /// One page of history. The feed never downloads the whole channel.
  static const int pageSize = 25;

  CollectionReference<Map<String, dynamic>> get _messages => _firestore
      .collection('globalChat')
      .doc(channelId)
      .collection('messages');

  DocumentReference<Map<String, dynamic>> _senderState(String uid) => _firestore
      .collection('globalChat')
      .doc(channelId)
      .collection('senders')
      .doc(uid);

  User get _user {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('You must be signed in to use Global Chat.');
    }
    return user;
  }

  /// The newest [limit] messages, newest first.
  ///
  /// Ordering is `sentAt` descending; Firestore appends `__name__` in the
  /// same direction automatically, so two messages written in the same
  /// millisecond still have one stable order and paging can never
  /// interleave them differently between pages.
  ///
  /// Incremental history is a *growing window* on this single ordered
  /// query rather than a series of `startAfter` cursors stitched
  /// together client-side: one query means one source of truth for order,
  /// so a page boundary cannot duplicate or reorder a message even while
  /// new ones arrive at the head.
  Stream<GlobalChatFeed> watchMessages({int limit = pageSize}) {
    return _messages
        .orderBy('sentAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => GlobalChatFeed(
            messages: snapshot.docs
                .map(GlobalMessage.fromFirestore)
                .toList(growable: false),
            // A full page back means there is very likely older history
            // beyond the current window.
            hasMore: snapshot.docs.length >= limit,
            // Firestore serves the local cache while offline instead of
            // erroring, so this is the only honest way to tell the reader
            // they may not be seeing the live channel.
            isFromCache: snapshot.metadata.isFromCache,
          ),
        );
  }

  /// Sends to the community channel.
  ///
  /// Copies identity from the sender's own profile document because rules
  /// verify those fields against that same document — reading it here
  /// keeps the client honest instead of trusting whatever the UI happens
  /// to hold in memory.
  Future<void> sendMessage(String rawContent) async {
    final user = _user;
    final content = rawContent.trim();

    if (content.isEmpty) {
      throw StateError('Write something first.');
    }
    if (content.length > maxMessageLength) {
      throw StateError(
        'Global Chat messages are limited to $maxMessageLength characters.',
      );
    }

    final profile = await _firestore.collection('users').doc(user.uid).get();
    final data = profile.data() ?? const <String, dynamic>{};
    final displayName = data['displayName'];
    if (displayName is! String || displayName.isEmpty) {
      throw StateError(
        'Your profile needs a display name before you can post here.',
      );
    }

    // The staff badge must match the ID token's role claim, which is what
    // rules compare against. Reading it from the token (not from a
    // Firestore field) is the whole point: a profile field would be
    // self-writable.
    final token = await user.getIdTokenResult();
    final role = token.claims?['role'];
    final isStaff =
        role is String &&
        const ['moderator', 'admin', 'superAdmin'].contains(role);

    final message = _messages.doc();
    final state = _senderState(user.uid);

    // The window counter has to advance by exactly one, so the current
    // value is read first. Rules re-derive the same decision from the
    // stored document, so a client that lies here is rejected rather
    // than believed — this read only decides which SHAPE to write.
    final existing = await state.get();
    final existingData = existing.data();
    final windowStartedAt =
        (existingData?['windowStartAt'] as Timestamp?)?.toDate();
    final windowLive =
        windowStartedAt != null &&
        DateTime.now().toUtc().difference(windowStartedAt.toUtc()) <
            fixedWindow;
    final windowCount = (existingData?['windowCount'] as num?)?.toInt() ?? 0;

    final batch = _firestore.batch();

    batch.set(message, {
      'senderId': user.uid,
      'senderName': displayName,
      'senderPhotoUrl': data['photoUrl'],
      'senderIsCreator': (data['accountType'] as String?) == 'creator',
      'senderIsStaff': isStaff,
      'content': content,
      'sentAt': FieldValue.serverTimestamp(),
      'isDeleted': false,
      'deletedBy': null,
      'deletedAt': null,
    });
    batch.set(state, {
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageId': message.id,
      // Continue the running window, or open a fresh one.
      'windowStartAt': windowLive
          ? existingData!['windowStartAt']
          : FieldValue.serverTimestamp(),
      'windowCount': windowLive ? windowCount + 1 : 1,
    });

    await batch.commit();
  }

  /// The sender's current rate-limit state, so the composer can explain
  /// a refusal instead of showing a generic failure. Rules remain the
  /// enforcement; this is only for the message shown to the person.
  Future<GlobalSendAllowance> sendAllowance() async {
    final user = _auth.currentUser;
    if (user == null) return const GlobalSendAllowance.allowed();

    final snapshot = await _senderState(user.uid).get();
    final data = snapshot.data();
    if (data == null) return const GlobalSendAllowance.allowed();

    final now = DateTime.now().toUtc();
    final lastAt = (data['lastMessageAt'] as Timestamp?)?.toDate().toUtc();
    final windowStartAt =
        (data['windowStartAt'] as Timestamp?)?.toDate().toUtc();
    final windowCount = (data['windowCount'] as num?)?.toInt() ?? 0;

    if (windowStartAt != null &&
        now.difference(windowStartAt) < fixedWindow &&
        windowCount >= fixedWindowLimit) {
      return GlobalSendAllowance.blocked(
        retryAfter: windowStartAt.add(fixedWindow).difference(now),
        reason: GlobalSendBlock.hourlyLimit,
      );
    }
    if (lastAt != null && now.difference(lastAt) < sendCooldown) {
      return GlobalSendAllowance.blocked(
        retryAfter: lastAt.add(sendCooldown).difference(now),
        reason: GlobalSendBlock.cooldown,
      );
    }
    return const GlobalSendAllowance.allowed();
  }

  /// Soft-deletes a message: authors remove their own, platform staff
  /// remove anyone's. Rules enforce which of those applies; the document
  /// survives with empty content so the feed shows a removal rather than
  /// silently losing a reply's context, and
  /// `functions/moderation/global_chat.js` writes an admin audit entry
  /// whenever the remover is not the author.
  Future<void> deleteMessage(String messageId) async {
    final user = _user;
    await _messages.doc(messageId).update({
      'isDeleted': true,
      'deletedBy': user.uid,
      'deletedAt': FieldValue.serverTimestamp(),
      'content': '',
    });
  }

  /// The uids this account has blocked. Global Chat is public, so a
  /// reader-side filter is the only place blocking can apply: rules
  /// cannot filter one shared query differently per reader, and the
  /// blocked list of OTHER users is deliberately not readable.
  ///
  /// Consequence, stated rather than hidden: you never see messages from
  /// someone you blocked, but blocking is one-directional here — someone
  /// who blocked you can still see your public messages.
  Stream<Set<String>> watchBlockedUserIds() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value(const <String>{});
    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('blocked')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.id).toSet());
  }
}
