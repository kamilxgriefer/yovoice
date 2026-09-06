import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_mentions.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// The `@…` the caller is typing right now.
@immutable
class MentionQuery {
  const MentionQuery({
    required this.start,
    required this.end,
    required this.prefix,
  });

  /// Index of the `@` itself.
  final int start;

  /// Exclusive end — the caret.
  final int end;

  /// What was typed after the `@`.
  final String prefix;
}

/// Longest name a caller can plausibly be part-way through typing. Past
/// it the `@` is treated as ordinary punctuation and the list closes.
const int _maxMentionQueryLength = 32;

/// The active mention query at [cursor], or null when the caret is not
/// inside one.
MentionQuery? mentionQueryAt(String text, int cursor) {
  if (cursor < 0 || cursor > text.length) return null;
  for (var index = cursor - 1; index >= 0; index -= 1) {
    if (cursor - index - 1 > _maxMentionQueryLength) return null;
    final character = text[index];
    if (character == '\n') return null;
    if (character == '@') {
      if (index > 0) {
        final previous = text.codeUnitAt(index - 1);
        // `me@example.com` is an address, not a mention.
        final isWord =
            (previous >= 0x30 && previous <= 0x39) ||
            (previous >= 0x41 && previous <= 0x5A) ||
            (previous >= 0x61 && previous <= 0x7A) ||
            previous == 0x5F ||
            previous == 0x40 ||
            previous > 0x7F;
        if (isWord) return null;
      }
      return MentionQuery(
        start: index,
        end: cursor,
        prefix: text.substring(index + 1, cursor),
      );
    }
  }
  return null;
}

/// The text and caret after picking [candidate] for [query].
({String text, int selection}) applyMention(
  String text,
  MentionQuery query,
  MentionCandidate candidate,
) {
  final tail = text.substring(query.end);
  final needsSpace = tail.isEmpty || !tail.startsWith(' ');
  final inserted = '@${candidate.displayName}${needsSpace ? ' ' : ''}';
  return (
    text: '${text.substring(0, query.start)}$inserted$tail',
    selection: query.start + inserted.length,
  );
}

/// A comment composer whose `@` opens an inline list of the caller's own
/// friends and inserts the chosen name as plain text.
///
/// Nothing structured is sent: the name lands in the message body and the
/// deployed `createMomentComment` contract is untouched. See
/// [MentionText] for the matching read side.
class MentionComposerField extends StatefulWidget {
  const MentionComposerField({
    required this.controller,
    required this.directory,
    required this.hintText,
    this.focusNode,
    this.enabled = true,
    this.minLines = 1,
    this.maxLines = 3,
    this.textInputAction = TextInputAction.send,
    this.onSubmitted,
    this.fieldKey,
    this.maxSuggestions = 5,
    super.key,
  });

  final TextEditingController controller;
  final MentionDirectory directory;
  final String hintText;
  final FocusNode? focusNode;
  final bool enabled;
  final int minLines;
  final int maxLines;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Key? fieldKey;
  final int maxSuggestions;

  @override
  State<MentionComposerField> createState() => _MentionComposerFieldState();
}

class _MentionComposerFieldState extends State<MentionComposerField> {
  MentionQuery? _query;
  List<MentionCandidate> _suggestions = const <MentionCandidate>[];

  /// The exact `@…` run the caller has already resolved or dismissed.
  ///
  /// Keyed by the run's TEXT, not its position: after picking, the field
  /// holds `@Ada Lovelace ` and the caret is still inside that run, so a
  /// position-keyed guard would reopen the picker on the very next
  /// rebuild and offer the name that was just inserted. Editing the run
  /// changes its text and the picker comes back.
  String? _dismissedRun;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_syncQuery);
  }

  @override
  void didUpdateWidget(covariant MentionComposerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_syncQuery);
      widget.controller.addListener(_syncQuery);
    }
    if (oldWidget.directory != widget.directory ||
        oldWidget.maxSuggestions != widget.maxSuggestions) {
      _syncQuery();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncQuery);
    super.dispose();
  }

  void _syncQuery() {
    final value = widget.controller.value;
    final selection = value.selection;
    final cursor = selection.isValid && selection.isCollapsed
        ? selection.baseOffset
        : value.text.length;
    final query = widget.enabled ? mentionQueryAt(value.text, cursor) : null;
    final run = query == null
        ? null
        : value.text.substring(query.start, query.end);
    if (run != _dismissedRun) _dismissedRun = null;
    final suggestions = query == null || _dismissedRun != null
        ? const <MentionCandidate>[]
        : widget.directory.suggest(query.prefix, limit: widget.maxSuggestions);
    if (query?.start == _query?.start &&
        query?.end == _query?.end &&
        listEquals(suggestions, _suggestions)) {
      return;
    }
    setState(() {
      _query = query;
      _suggestions = suggestions;
    });
  }

  void _dismiss() {
    if (_suggestions.isEmpty) return;
    final query = _query;
    setState(() {
      _dismissedRun = query == null
          ? null
          : widget.controller.text.substring(query.start, query.end);
      _suggestions = const <MentionCandidate>[];
    });
  }

  void _pick(MentionCandidate candidate) {
    final query = _query;
    if (query == null) return;
    final result = applyMention(widget.controller.text, query, candidate);
    widget.controller.value = TextEditingValue(
      text: result.text,
      selection: TextSelection.collapsed(offset: result.selection),
    );
    setState(() {
      _query = null;
      _suggestions = const <MentionCandidate>[];
      // The caret still sits inside the run that was just completed;
      // remembering it keeps the picker from re-offering the name the
      // caller has already chosen.
      _dismissedRun = result.text.substring(query.start, result.selection);
    });
    widget.focusNode?.requestFocus();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    if (_suggestions.isEmpty) return KeyEventResult.ignored;
    _dismiss();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_suggestions.isNotEmpty) ...[
          MentionSuggestionList(
            suggestions: _suggestions,
            onSelected: _pick,
            onDismiss: _dismiss,
          ),
          const SizedBox(height: 8),
        ],
        Focus(
          onKeyEvent: _handleKey,
          child: TextField(
            key: widget.fieldKey,
            controller: widget.controller,
            focusNode: widget.focusNode,
            minLines: widget.minLines,
            maxLines: widget.maxLines,
            enabled: widget.enabled,
            textInputAction: widget.textInputAction,
            onSubmitted: widget.onSubmitted,
            onTap: _syncQuery,
            style: TextStyle(color: palette.textPrimary),
            decoration: InputDecoration(
              hintText: widget.hintText,
              hintStyle: TextStyle(color: palette.textTertiary),
              filled: true,
              fillColor: palette.surfaceSunken,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The inline `@` picker: the caller's friends, filtered by what they
/// typed. Never a public directory search.
class MentionSuggestionList extends StatelessWidget {
  const MentionSuggestionList({
    required this.suggestions,
    required this.onSelected,
    this.onDismiss,
    super.key,
  });

  final List<MentionCandidate> suggestions;
  final ValueChanged<MentionCandidate> onSelected;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return Container(
      key: const ValueKey('moment-mention-suggestions'),
      constraints: const BoxConstraints(maxHeight: 216),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    copy.text('Mention a friend', 'Oznacz znajomego'),
                    style: TextStyle(
                      color: palette.textTertiary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .2,
                    ),
                  ),
                ),
                if (onDismiss != null)
                  IconButton(
                    key: const ValueKey('moment-mention-suggestions-close'),
                    onPressed: onDismiss,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: 36,
                      height: 36,
                    ),
                    padding: EdgeInsets.zero,
                    tooltip: copy.text(
                      'Close suggestions',
                      'Zamknij podpowiedzi',
                    ),
                    icon: Icon(
                      Icons.close_rounded,
                      size: 17,
                      color: palette.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 6),
              itemCount: suggestions.length,
              itemBuilder: (context, index) {
                final candidate = suggestions[index];
                return Semantics(
                  button: true,
                  label: copy.template(
                    'Mention {name}',
                    'Oznacz: {name}',
                    values: <String, Object>{'name': candidate.displayName},
                  ),
                  child: InkWell(
                    key: ValueKey('moment-mention-option-${candidate.userId}'),
                    onTap: () => onSelected(candidate),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 44),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          UserAvatar(
                            radius: 14,
                            userId: candidate.userId,
                            displayName: candidate.displayName,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              candidate.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: palette.textPrimary,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            '@',
                            style: TextStyle(
                              color: palette.interactiveForeground,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
