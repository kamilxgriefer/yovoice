import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/auth/data/reauthentication_service.dart';
import 'package:yovoice/features/pages/presentation/page_delete_copy.dart';
import 'package:yovoice/features/pages/presentation/page_profile_copy.dart';
import 'package:yovoice/features/pages/presentation/pages_copy.dart';

/// Forces a new ID token and answers whether there was still a user to mint
/// one for (the account-deletion pattern: after a re-authentication the
/// CACHED token is what a callable sends, and it may still carry the old
/// `auth_time`).
typedef PageDeleteTokenRefresher = Future<bool> Function();

Future<bool> _refreshIdToken() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return false;
  await user.getIdToken(true);
  return true;
}

/// The fresh sign-in "Usuń teraz, nie czekaj" needs (ADR-236).
///
/// `managePageDeletionV1 {op:"purgeNow"}` is the one irreversible Page op,
/// so the server refuses a sign-in older than five minutes
/// (`requireRecentPrivilegedAuthentication`, the account-deletion rule): a
/// session somebody else got hold of can start a deletion, which the owner
/// can take back for 30 days, but cannot skip the wait.
///
/// This is the client half, the same three routes the account deletion
/// screen uses ([ReauthenticationClient]): Google, Apple, or the password in
/// a small dialog. [PageReauthOutcome.confirmed] once the owner proved it is
/// them AND a token with the new sign-in time is in hand; a closed password
/// dialog is [PageReauthOutcome.cancelled] (silent), and everything else is
/// [PageReauthOutcome.failed], which the caller says with
/// [PageDeleteCopy.confirmIdentityFailed].
Future<PageReauthOutcome> confirmIdentityForPageDeletion(
  BuildContext context, {
  ReauthenticationClient? client,
  PageDeleteTokenRefresher? refreshIdToken,
}) async {
  final reauthentication =
      client ??
      ReauthenticationService(
        signedOutMessage: 'You must be signed in to delete your Page.',
      );
  final ReauthenticationMethod method;
  try {
    method = reauthentication.method;
  } catch (_) {
    return PageReauthOutcome.failed;
  }
  try {
    switch (method) {
      case ReauthenticationMethod.google:
        await reauthentication.reauthenticateWithGoogle();
      case ReauthenticationMethod.apple:
        await reauthentication.reauthenticateWithApple();
      case ReauthenticationMethod.password:
        final password = await showDialog<String>(
          context: context,
          builder: (_) => const _PagePasswordDialog(),
        );
        if (password == null) return PageReauthOutcome.cancelled;
        await reauthentication.reauthenticateWithPassword(password);
      case ReauthenticationMethod.unavailable:
        // No provider this app can re-challenge in place: signing out and in
        // again is the route, and the failure copy names it.
        return PageReauthOutcome.failed;
    }
    final refreshed = await (refreshIdToken ?? _refreshIdToken)();
    return refreshed ? PageReauthOutcome.confirmed : PageReauthOutcome.failed;
  } catch (_) {
    // A wrong password, a dismissed provider sheet, a second factor this
    // step cannot drive, no network: nothing was deleted either way.
    return PageReauthOutcome.failed;
  }
}

enum PageReauthOutcome {
  /// A fresh sign-in is in hand: send the op again.
  confirmed,

  /// The owner closed the password dialog: say nothing.
  cancelled,

  /// It could not be confirmed: say so; nothing was deleted.
  failed,
}

/// The password challenge. It owns its controller (one disposed the moment
/// `showDialog` completes is still read while the dialog animates out).
class _PagePasswordDialog extends StatefulWidget {
  const _PagePasswordDialog();

  @override
  State<_PagePasswordDialog> createState() => _PagePasswordDialogState();
}

class _PagePasswordDialogState extends State<_PagePasswordDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final password = _controller.text;
    if (password.isEmpty) return;
    Navigator.pop(context, password);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final copy = PagesCopy(AppLocalizations.of(context));
    return AlertDialog(
      key: const ValueKey('page-delete-password-dialog'),
      backgroundColor: palette.surfaceRaised,
      scrollable: true,
      title: Text(
        copy.confirmIdentityTitle,
        style: TextStyle(color: palette.textPrimary),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              copy.confirmIdentityBody,
              style: TextStyle(color: palette.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('page-delete-password-field'),
              controller: _controller,
              autofocus: true,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(labelText: copy.passwordLabel),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(copy.cancel),
        ),
        FilledButton(
          key: const ValueKey('page-delete-password-submit'),
          onPressed: _controller.text.isEmpty ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: colors.error,
            foregroundColor: colors.onError,
          ),
          child: Text(copy.delete),
        ),
      ],
    );
  }
}
