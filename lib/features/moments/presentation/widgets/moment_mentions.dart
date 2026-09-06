import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';

/// @-mentions in Voice Moment comments, end to end: who a mention may
/// resolve to, how one is found inside a comment, and how it renders.
///
/// A mention is **plain text inside the comment body**. The deployed
/// `createMomentComment` callable accepts an exact input contract
/// (`momentId`, `text`, `requestId`) and the server rejects anything
/// else, so there is no mention field on the wire, no mention document,
/// and — because clients cannot write `users/{uid}/notifications` — no
/// mention notification. Resolution is a *rendering* decision made per
/// viewer against people that viewer can already see: the participants
/// of the comment thread itself, plus the viewer's own friends.
///
/// Anything that does not resolve stays ordinary text. A mention never
/// invents an identity and never renders as a link that goes nowhere.

/// Someone an `@name` may resolve to for the current viewer.
@immutable
class MentionCandidate {
  MentionCandidate({required this.userId, required String displayName})
    : displayName = displayName.trim(),
      matchKey = normalizeMentionName(displayName);

  final String userId;
  final String displayName;

  /// Case- and whitespace-insensitive matching key.
  final String matchKey;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MentionCandidate &&
          userId == other.userId &&
          displayName == other.displayName;

  @override
  int get hashCode => Object.hash(userId, displayName);
}

/// Lowercases and collapses internal whitespace so `@Nadia  Rutkowska`
/// still resolves to `Nadia Rutkowska`.
String normalizeMentionName(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

bool _isMentionWordCharacter(int codeUnit) =>
    (codeUnit >= 0x30 && codeUnit <= 0x39) || // 0-9
    (codeUnit >= 0x41 && codeUnit <= 0x5A) || // A-Z
    (codeUnit >= 0x61 && codeUnit <= 0x7A) || // a-z
    codeUnit == 0x5F || // _
    codeUnit > 0x7F; // any non-ASCII letter (ą, ł, ż, …)

/// A resolved mention and where it ends inside the source text.
typedef MentionMatch = ({MentionCandidate candidate, int end});

/// The people the current viewer's mentions may resolve to.
///
/// Longest display name first, so `@Ada Lovelace` wins over `@Ada` when
/// both are known.
@immutable
class MentionDirectory {
  factory MentionDirectory(Iterable<MentionCandidate> candidates) {
    final byKey = <String, MentionCandidate>{};
    for (final candidate in candidates) {
      if (candidate.matchKey.isEmpty || candidate.userId.isEmpty) continue;
      // First writer wins: thread participants are passed before friends,
      // and a name the viewer just read in the thread is the one they
      // meant.
      byKey.putIfAbsent(candidate.matchKey, () => candidate);
    }
    final ordered = byKey.values.toList(growable: false)
      ..sort((a, b) {
        final byLength = b.matchKey.length.compareTo(a.matchKey.length);
        return byLength != 0 ? byLength : a.matchKey.compareTo(b.matchKey);
      });
    return MentionDirectory._(List<MentionCandidate>.unmodifiable(ordered));
  }

  const MentionDirectory._(this.candidates);

  static const MentionDirectory empty = MentionDirectory._(
    <MentionCandidate>[],
  );

  final List<MentionCandidate> candidates;

  bool get isEmpty => candidates.isEmpty;

  bool get isNotEmpty => candidates.isNotEmpty;

  /// The candidate named immediately after the `@` at [atIndex], or null.
  ///
  /// The character before the `@` must not be part of a word, so an email
  /// address never becomes a mention, and the character after the name
  /// must not be either, so `@Ada` inside `@Adamska` stays plain.
  MentionMatch? matchAt(String text, int atIndex) {
    if (atIndex < 0 || atIndex >= text.length || text[atIndex] != '@') {
      return null;
    }
    if (atIndex > 0 && _isMentionWordCharacter(text.codeUnitAt(atIndex - 1))) {
      return null;
    }
    final lowered = text.toLowerCase();
    final start = atIndex + 1;
    for (final candidate in candidates) {
      // The stored name first, then its whitespace-collapsed form: a
      // display name carrying a double space still resolves either way.
      for (final form in <String>{
        candidate.displayName.toLowerCase(),
        candidate.matchKey,
      }) {
        if (form.isEmpty) continue;
        final end = start + form.length;
        if (end > text.length) continue;
        if (lowered.substring(start, end) != form) continue;
        if (end < text.length &&
            _isMentionWordCharacter(text.codeUnitAt(end))) {
          continue;
        }
        return (candidate: candidate, end: end);
      }
    }
    return null;
  }

  /// Suggestions for a typed `@prefix`, matched on any word of the name.
  List<MentionCandidate> suggest(String prefix, {int limit = 5}) {
    final needle = normalizeMentionName(prefix);
    final matches = <MentionCandidate>[
      for (final candidate in candidates)
        if (needle.isEmpty || _matchesPrefix(candidate.matchKey, needle))
          candidate,
    ]..sort((a, b) => a.matchKey.compareTo(b.matchKey));
    return List<MentionCandidate>.unmodifiable(
      matches.length <= limit ? matches : matches.take(limit),
    );
  }

  static bool _matchesPrefix(String name, String needle) {
    if (name.startsWith(needle)) return true;
    for (final word in name.split(' ')) {
      if (word.startsWith(needle)) return true;
    }
    return false;
  }
}

/// One run of a comment body: plain copy, or a resolved mention.
@immutable
class MentionSegment {
  const MentionSegment({required this.text, this.candidate});

  final String text;
  final MentionCandidate? candidate;

  bool get isMention => candidate != null;
}

/// Splits [text] into plain runs and resolved mentions.
List<MentionSegment> splitMentions(String text, MentionDirectory directory) {
  if (text.isEmpty) return const <MentionSegment>[];
  if (directory.isEmpty || !text.contains('@')) {
    return <MentionSegment>[MentionSegment(text: text)];
  }
  final segments = <MentionSegment>[];
  final buffer = StringBuffer();
  var index = 0;
  while (index < text.length) {
    if (text[index] == '@') {
      final match = directory.matchAt(text, index);
      if (match != null) {
        if (buffer.isNotEmpty) {
          segments.add(MentionSegment(text: buffer.toString()));
          buffer.clear();
        }
        segments.add(
          MentionSegment(
            text: text.substring(index, match.end),
            candidate: match.candidate,
          ),
        );
        index = match.end;
        continue;
      }
    }
    buffer.write(text[index]);
    index += 1;
  }
  if (buffer.isNotEmpty) segments.add(MentionSegment(text: buffer.toString()));
  return segments;
}

/// Comment copy with its resolvable `@mentions` tinted and tappable.
///
/// An unresolvable `@something` renders exactly like the surrounding
/// text: no tint, no tap target, no fabricated profile.
class MentionText extends StatefulWidget {
  const MentionText({
    required this.text,
    required this.directory,
    this.style,
    this.mentionStyle,
    this.leadingSpans = const <InlineSpan>[],
    this.maxLines,
    this.overflow = TextOverflow.clip,
    this.onMentionTap,
    super.key,
  });

  final String text;
  final MentionDirectory directory;
  final TextStyle? style;

  /// Defaults to the palette's interactive foreground, semi-bold.
  final TextStyle? mentionStyle;

  /// Rendered before the body — the author's name on a one-line preview
  /// row, for example.
  final List<InlineSpan> leadingSpans;
  final int? maxLines;
  final TextOverflow overflow;

  /// Defaults to the app-wide profile preview sheet.
  final void Function(MentionCandidate candidate)? onMentionTap;

  @override
  State<MentionText> createState() => _MentionTextState();
}

class _MentionTextState extends State<MentionText> {
  /// Kept across builds and disposed once. Disposing a recognizer that a
  /// pointer is still resting on throws, and a comment list rebuilds on
  /// every friends emission.
  final Map<String, TapGestureRecognizer> _recognizers =
      <String, TapGestureRecognizer>{};

  @override
  void dispose() {
    for (final recognizer in _recognizers.values) {
      recognizer.dispose();
    }
    _recognizers.clear();
    super.dispose();
  }

  void _open(MentionCandidate candidate) {
    final handler = widget.onMentionTap;
    if (handler != null) {
      handler(candidate);
      return;
    }
    unawaited(
      showProfilePreview(
        context,
        userId: candidate.userId,
        displayName: candidate.displayName,
      ),
    );
  }

  TapGestureRecognizer _recognizerFor(MentionCandidate candidate) {
    final recognizer = _recognizers.putIfAbsent(
      candidate.userId,
      TapGestureRecognizer.new,
    );
    recognizer.onTap = () => _open(candidate);
    return recognizer;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final baseStyle = widget.style;
    final mentionStyle =
        widget.mentionStyle ??
        (baseStyle ?? const TextStyle()).copyWith(
          color: palette.interactiveForeground,
          fontWeight: FontWeight.w700,
        );
    final spans = <InlineSpan>[
      ...widget.leadingSpans,
      for (final segment in splitMentions(widget.text, widget.directory))
        if (segment.candidate case final candidate?)
          TextSpan(
            text: segment.text,
            style: mentionStyle,
            recognizer: _recognizerFor(candidate),
          )
        else
          TextSpan(text: segment.text),
    ];
    return Text.rich(
      TextSpan(style: baseStyle, children: spans),
      maxLines: widget.maxLines,
      overflow: widget.overflow,
    );
  }
}

/// The caller's own friends, live, as mention candidates.
///
/// A private list the caller already reads elsewhere in the app — never a
/// directory search, and never anyone the caller cannot already see.
/// Fails quiet: with no Firebase app, no session, or a stream error the
/// candidate list stays empty and mentions degrade to plain text.
class MentionFriendsSource extends ChangeNotifier {
  MentionFriendsSource({
    Stream<List<FriendUser>>? friendsStream,
    FriendService? friendService,
  }) {
    final stream = friendsStream ?? _resolveStream(friendService);
    if (stream == null) return;
    _subscription = stream.listen(
      (friends) {
        _candidates = List<MentionCandidate>.unmodifiable(<MentionCandidate>[
          for (final friend in friends)
            if (friend.id.isNotEmpty && friend.displayName.trim().isNotEmpty)
              MentionCandidate(
                userId: friend.id,
                displayName: friend.displayName,
              ),
        ]);
        notifyListeners();
      },
      onError: (Object _) {
        // A friends read that fails must never take a comment thread with
        // it. Mentions stay plain text.
      },
    );
  }

  static Stream<List<FriendUser>>? _resolveStream(FriendService? injected) {
    try {
      return (injected ?? FriendService()).watchFriends();
    } catch (_) {
      // No Firebase app, or nobody signed in.
      return null;
    }
  }

  StreamSubscription<List<FriendUser>>? _subscription;
  List<MentionCandidate> _candidates = const <MentionCandidate>[];

  List<MentionCandidate> get candidates => _candidates;

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    super.dispose();
  }
}
