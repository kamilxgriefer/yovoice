import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_palette.dart';

/// The six message reactions, in picker order: exactly the direct-message
/// vocabulary (`ALLOWED_DIRECT_REACTIONS` in
/// `functions/messaging/direct_integrity.js`), which the server-channel
/// reaction callable imports as well. A reaction outside this list is refused
/// by both callables.
const List<String> kMessageReactionEmojis = <String>[
  '❤️',
  '😂',
  '🔥',
  '😮',
  '😢',
  '👍',
];

/// The one-line reaction summary a direct-message bubble draws: every distinct
/// emoji once, with a count when more than one person chose it
/// (`❤️ 2 😂`). Blank values are ignored. Order follows first appearance.
String messageReactionSummary(Iterable<String> reactions) {
  final counts = <String, int>{};
  for (final reaction in reactions) {
    if (reaction.trim().isEmpty) continue;
    counts[reaction] = (counts[reaction] ?? 0) + 1;
  }
  return counts.entries
      .map(
        (entry) => entry.value > 1 ? '${entry.key} ${entry.value}' : entry.key,
      )
      .join(' ');
}

/// The flat reaction pill a direct-message bubble shows under its body: it
/// sits in the thread rather than floating above it, so it carries a hairline
/// and no shadow. Draws nothing when there is no reaction. Carries no copy;
/// the emoji and counts are the content.
class MessageReactionSummaryPill extends StatelessWidget {
  const MessageReactionSummaryPill({required this.reactions, super.key});

  /// The stored `uid -> emoji` values of one message.
  final Iterable<String> reactions;

  @override
  Widget build(BuildContext context) {
    final summary = messageReactionSummary(reactions);
    if (summary.isEmpty) return const SizedBox.shrink();
    final palette = context.appPalette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Text(summary, style: const TextStyle(fontSize: 13)),
    );
  }
}

/// The reaction row at the top of a message actions sheet: the six emoji as
/// large round targets. The viewer's current reaction is marked, so choosing
/// it again reads as "take it back" — the toggle both reaction callables
/// implement (one reaction per person; the same emoji again removes it).
class MessageReactionPickerRow extends StatelessWidget {
  const MessageReactionPickerRow({
    required this.onReaction,
    this.selected,
    super.key,
  });

  final ValueChanged<String> onReaction;

  /// The viewer's current reaction, if any.
  final String? selected;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: kMessageReactionEmojis
          .map(
            (emoji) => Semantics(
              selected: emoji == selected,
              child: InkWell(
                key: ValueKey('message-reaction-$emoji'),
                onTap: () => onReaction(emoji),
                customBorder: const CircleBorder(),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: emoji == selected
                      ? BoxDecoration(
                          shape: BoxShape.circle,
                          color: palette.surfaceMuted,
                          border: Border.all(color: palette.focus),
                        )
                      : null,
                  child: Text(emoji, style: const TextStyle(fontSize: 27)),
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}
