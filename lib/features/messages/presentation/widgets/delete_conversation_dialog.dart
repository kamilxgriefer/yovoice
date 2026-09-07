import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';

/// Confirms deleting a direct conversation for the signed-in account only.
///
/// Shared by the chat list row's options sheet and the chat screen's overflow
/// menu so both entry points make the same promise in the same words. The body
/// states the semantics outright — this removes the conversation for you, the
/// other person keeps theirs — because "Delete chat" reads, to most people, as
/// deleting it everywhere, and this one does not do that.
///
/// Returns `true` only when the destructive action was chosen; `null` when the
/// dialog was dismissed by tapping outside or pressing back.
Future<bool?> confirmDeleteConversation(
  BuildContext context, {
  required String name,
}) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final palette = dialogContext.appPalette;
      final colors = Theme.of(dialogContext).colorScheme;
      final copy = AppLocalizations.of(dialogContext);
      return AlertDialog(
        key: const ValueKey('conversation-delete-dialog'),
        backgroundColor: palette.surfaceRaised,
        // The body is a full sentence explaining the semantics, so it has to
        // survive an enlarged text scale on a short phone. Material's default
        // dialog already caps its own width on desktop.
        scrollable: true,
        title: Text(
          copy.text('Delete chat?', 'Usunąć czat?'),
          style: TextStyle(color: palette.textPrimary),
        ),
        content: Text(
          copy.template(
            'This removes the conversation with {name} and its messages for '
            'you only. {name} keeps their copy. If they message you again, '
            'the chat comes back with the new messages only.',
            'To usunie tylko u Ciebie rozmowę z {name} wraz z wiadomościami. '
            '{name} zachowa swoją kopię. Jeśli ta osoba napisze ponownie, '
            'czat wróci wyłącznie z nowymi wiadomościami.',
            values: <String, Object>{'name': name},
          ),
          style: TextStyle(color: palette.textSecondary),
        ),
        actions: [
          TextButton(
            key: const ValueKey('conversation-delete-cancel'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(copy.text('Cancel', 'Anuluj')),
          ),
          FilledButton(
            key: const ValueKey('conversation-delete-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: colors.error,
              foregroundColor: colors.onError,
            ),
            child: Text(copy.text('Delete', 'Usuń')),
          ),
        ],
      );
    },
  );
}
