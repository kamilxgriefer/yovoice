import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/account/data/account_deletion_service.dart';
import 'package:yovoice/features/auth/data/auth_service.dart';
import 'package:yovoice/features/auth/data/reauthentication_service.dart';
import 'package:yovoice/features/auth/presentation/auth_error_localizer.dart';
import 'package:yovoice/features/settings/presentation/widgets/delete_account_consequences.dart';
import 'package:yovoice/shared/widgets/backgrounds/yo_page_background.dart';
import 'package:yovoice/shared/widgets/buttons/yo_icon_button.dart';

typedef DeleteAccountUrlOpener = Future<void> Function(String url);
typedef DeleteAccountSignOut = Future<void> Function();

/// The public page a Play reviewer, and anybody who cannot open the app, is
/// sent to. It carries the same deleted/retained lists as this screen.
const deleteAccountWebUrl = 'https://yovoice.app/delete-account';

/// The rights mailbox the privacy policy and the website already publish.
const deleteAccountMailbox = 'privacy@yovoice.app';

enum _Stage { review, working, requested }

/// `Settings → Account → Delete account`.
///
/// Deletion is a mark-and-sweep pipeline, so this screen never claims the data
/// is gone. It states exactly what will be deleted and what is kept, proves
/// the person is who they say they are, and takes a typed confirmation.
///
/// The order after that is deliberate, and it is **not** "call the callable,
/// then sign out". `deleteAccountSelfV1` only *accepts* the request — the
/// sweep runs afterwards, on the server — so the screen moves to a terminal
/// pending panel (`_Stage.requested`) that says the deletion has started and
/// is still running. Signing out happens later and only when the person taps
/// **Done** on that panel (`_finish`), which is also the only way out of the
/// stage: `PopScope` keeps `canPop` false there. Signing out inside
/// `_beginDeletion` would tear the session down underneath the panel the
/// person is still reading. The sign-out itself is best effort and never
/// blocks the exit — the account is disabled and its refresh tokens are
/// already revoked from the moment the request is accepted, and a half-working
/// app is a worse answer than a clean exit.
///
/// The email route that existed before this screen is preserved, demoted to a
/// secondary action: it is the only route for anybody the callable cannot
/// serve yet.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({
    super.key,
    this.isRootTab = false,
    this.deletionClient,
    this.reauthentication,
    this.signOut,
    this.openUrl,
  });

  /// True when this screen IS the shell's current content (a desktop content
  /// slot) rather than a pushed route: the shell owns navigation, so the
  /// screen draws no app bar of its own. Same flag, same meaning, as
  /// `SettingsScreen.isRootTab`.
  final bool isRootTab;

  final AccountDeletionClient? deletionClient;
  final ReauthenticationClient? reauthentication;

  /// Signing out is the last step of the flow. `AuthService.signOut` already
  /// unregisters the push token, clears the local message and offline-audio
  /// caches and invalidates every signed media grant, so this screen delegates
  /// rather than repeating that list and getting it wrong.
  final DeleteAccountSignOut? signOut;
  final DeleteAccountUrlOpener? openUrl;

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  static const _wideBreakpoint = 1024.0;
  static const _mediumBreakpoint = 600.0;
  static const _textMeasure = 560.0;

  late final AccountDeletionClient _deletion =
      widget.deletionClient ?? AccountDeletionService();
  late final ReauthenticationClient _reauthentication =
      widget.reauthentication ??
      ReauthenticationService(
        signedOutMessage: 'You must be signed in to delete your account.',
      );
  _Stage _stage = _Stage.review;
  String? _error;
  bool _retainedOpen = false;

  Future<void> _openUrl(String url) async {
    final opener = widget.openUrl;
    if (opener != null) {
      await opener(url);
      return;
    }
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ---------------------------------------------------------------- deletion

  Future<void> _beginDeletion() async {
    if (_stage != _Stage.review) return;
    setState(() => _error = null);

    final reauthenticated = await _reauthenticate();
    if (!mounted || !reauthenticated) return;

    final confirmed = await _confirm();
    if (!mounted || !confirmed) return;

    setState(() => _stage = _Stage.working);
    try {
      await _deletion.requestDeletion();
      if (!mounted) return;
      setState(() => _stage = _Stage.requested);
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          AppLocalizations.of(
            context,
          ).text('Your account is being deleted.', 'Twoje konto jest usuwane.'),
          Directionality.of(context),
          assertiveness: Assertiveness.assertive,
        ),
      );
    } on AccountDeletionFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.review;
        _error = _failureCopy(failure.kind);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.review;
        _error = localizedAuthError(context, error);
      });
    }
  }

  String _failureCopy(AccountDeletionFailureKind kind) {
    final copy = AppLocalizations.of(context);
    return switch (kind) {
      AccountDeletionFailureKind.recentSignInRequired => copy.text(
        'Your sign-in is no longer recent enough. Start again and confirm it '
            'is you.',
        'Twoje logowanie nie jest już wystarczająco świeże. Zacznij od nowa i '
            'potwierdź, że to Ty.',
      ),
      AccountDeletionFailureKind.unavailable => copy.text(
        'Deleting your account from here is not available yet. Email us and '
            'we will delete it for you.',
        'Usuwanie konta z tego miejsca nie jest jeszcze dostępne. Napisz do '
            'nas, a usuniemy je za Ciebie.',
      ),
      AccountDeletionFailureKind.rateLimited => copy.text(
        'Too many attempts. Please try again in a few minutes.',
        'Zbyt wiele prób. Spróbuj ponownie za kilka minut.',
      ),
      AccountDeletionFailureKind.signedOut => copy.text(
        'Your session has ended. Sign in again to delete your account.',
        'Twoja sesja wygasła. Zaloguj się ponownie, aby usunąć konto.',
      ),
      AccountDeletionFailureKind.unknown => copy.text(
        'We could not start the deletion. Try again.',
        'Nie udało się rozpocząć usuwania. Spróbuj ponownie.',
      ),
    };
  }

  // --------------------------------------------------------- reauthentication

  Future<bool> _reauthenticate() async {
    final copy = AppLocalizations.of(context);
    final ReauthenticationMethod method;
    try {
      method = _reauthentication.method;
    } catch (error) {
      if (mounted) setState(() => _error = localizedAuthError(context, error));
      return false;
    }

    switch (method) {
      case ReauthenticationMethod.google:
        return _runReauth(_reauthentication.reauthenticateWithGoogle);
      case ReauthenticationMethod.apple:
        return _runReauth(_reauthentication.reauthenticateWithApple);
      case ReauthenticationMethod.unavailable:
        setState(
          () => _error = copy.text(
            'Sign out and sign in again before deleting your account.',
            'Wyloguj się i zaloguj ponownie przed usunięciem konta.',
          ),
        );
        return false;
      case ReauthenticationMethod.password:
        final password = await _askForPassword();
        if (!mounted || password == null) return false;
        return _runReauth(
          () => _reauthentication.reauthenticateWithPassword(password),
        );
    }
  }

  Future<bool> _runReauth(Future<void> Function() operation) async {
    try {
      await operation();
      return true;
    } catch (error) {
      if (!mounted) return false;
      setState(() {
        _error = _isSecondFactorRequired(error)
            // An account with two-factor authentication turned on cannot
            // finish a re-authentication here: Firebase throws and this screen
            // has no second-factor step to drive. Through `localizedAuthError`
            // that became a generic message and a dead end — the users who
            // followed our own security advice locked out of the one
            // affordance Google Play requires. Until the resolver lands
            // (docs/Bugs.md, 2026-09-18) the honest answer names the route
            // that DOES work for them, in the same words as the button below.
            ? AppLocalizations.of(context).text(
                'Your account uses two-factor authentication, which we cannot '
                    'confirm on this screen yet. Use "Ask us by email instead" '
                    'below and we will delete your account for you.',
                'Twoje konto używa weryfikacji dwuskładnikowej, której nie '
                    'potrafimy jeszcze potwierdzić na tym ekranie. Użyj '
                    'przycisku „Poproś nas o to e-mailem” poniżej, a usuniemy '
                    'Twoje konto za Ciebie.',
              )
            : localizedAuthError(context, error);
      });
      return false;
    }
  }

  /// Firebase reports "this account has a second factor" two ways: a typed
  /// `FirebaseAuthMultiFactorException`, whose only constructor is private to
  /// the plugin, and an error CODE that differs by platform —
  /// `second-factor-required` on the native SDKs, `multi-factor-auth-required`
  /// on the web. Matching on both makes the branch reachable everywhere AND
  /// reachable from a test, which the typed exception alone is not.
  static bool _isSecondFactorRequired(Object error) =>
      error is FirebaseAuthMultiFactorException ||
      (error is FirebaseAuthException &&
          const {
            'second-factor-required',
            'multi-factor-auth-required',
          }.contains(error.code));

  Future<String?> _askForPassword() => showDialog<String>(
    context: context,
    builder: (_) => const _PasswordPromptDialog(),
  );

  // ------------------------------------------------------------ confirmation

  Future<bool> _confirm() async {
    final copy = AppLocalizations.of(context);
    final word = copy.text('DELETE', 'USUŃ');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _ConfirmDeletionDialog(word: word),
    );
    return confirmed == true;
  }

  // -------------------------------------------------------------- signing out

  Future<void> _finish() async {
    try {
      await (widget.signOut ?? AuthService().signOut)();
    } catch (_) {
      // Sign-out is best effort: the account is already disabled and its
      // refresh tokens are revoked by the pipeline. Never trap the person on
      // a terminal panel because the local sign-out failed.
    }
    if (mounted) Navigator.of(context).maybePop();
  }

  // -------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    return PopScope(
      // The request has been accepted and the session is about to end: the
      // only way out of this state is Done, which signs out.
      canPop: _stage == _Stage.review,
      child: Scaffold(
        backgroundColor: palette.background,
        appBar: widget.isRootTab
            ? null
            : AppBar(
                leading: _stage == _Stage.review
                    ? YoIconButton(
                        icon: Icons.arrow_back_rounded,
                        tooltip: copy.text('Back', 'Wstecz'),
                        onPressed: () => Navigator.maybePop(context),
                      )
                    : null,
                title: Text(copy.text('Delete account', 'Usuń konto')),
              ),
        body: YoPageBackground(
          section: YoPageSection.more,
          child: SafeArea(
            top: widget.isRootTab,
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (_stage == _Stage.requested) {
                  return _RequestedPanel(onDone: _finish);
                }
                return constraints.maxWidth >= _wideBreakpoint
                    ? _wideLayout()
                    : _columnLayout(constraints.maxWidth);
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Narrow and medium: one scrolling column. Narrow uses the full width with
  /// a page gutter; medium keeps the measure readable and centres it, rather
  /// than stretching a phone layout across a tablet.
  Widget _columnLayout(double width) {
    final narrow = width < _mediumBreakpoint;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(narrow ? 20 : 28, 20, narrow ? 20 : 28, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _textMeasure),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ..._headerSlivers(),
              const SizedBox(height: 22),
              ..._bodySlivers(),
              const SizedBox(height: 26),
              ..._actionSlivers(),
            ],
          ),
        ),
      ),
    );
  }

  /// Wide: the decision and its consequences side by side. The actions stay in
  /// view on the left while the list and the retained set scroll on the right,
  /// so a desktop reader never loses the thing they came to do — and this is
  /// not the phone column stretched to 1440 px.
  Widget _wideLayout() => Padding(
    padding: const EdgeInsets.fromLTRB(32, 28, 32, 32),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ..._headerSlivers(),
                const SizedBox(height: 26),
                ..._actionSlivers(),
              ],
            ),
          ),
        ),
        const SizedBox(width: 40),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _bodySlivers(),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  List<Widget> _headerSlivers() {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return [
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.errorContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(Icons.warning_rounded, color: colors.onErrorContainer),
        ),
      ),
      const SizedBox(height: 16),
      Semantics(
        header: true,
        // A 22 dp w900 headline at 200 % text is 44 dp, and the longest word
        // of the Polish sentence — "nieodwracalne" — is then wider than a
        // 320 dp column's text area. Flutter's only remaining option is to
        // break the word itself, and the frame reads "…jest ni / eodwracaln /
        // e", which on the one sentence that says the action cannot be undone
        // looks like a rendering fault rather than emphasis.
        //
        // Only the HEADLINE is clamped, and only where the column genuinely
        // cannot hold it. Body copy, the consequence list, the dialogs and
        // every control keep the full 200 %; no content and no functionality
        // is lost, and above ~340 dp (402 and up, where the word fits) the
        // headline is not clamped at all.
        child: LayoutBuilder(
          builder: (context, constraints) => MediaQuery.withClampedTextScaling(
            maxScaleFactor: constraints.maxWidth < 340 ? 1.4 : double.infinity,
            child: Text(
              copy.text(
                'Deleting your account is permanent. This is what happens.',
                'Usunięcie konta jest nieodwracalne. Oto co się stanie.',
              ),
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 22,
                height: 1.25,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.4,
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Text(
        copy.text(
          'This usually finishes within a few minutes, and always within 30 '
              'days. There is no undo.',
          'Zwykle kończy się to w ciągu kilku minut, najpóźniej w ciągu 30 dni. '
              'Tej operacji nie można cofnąć.',
        ),
        style: TextStyle(
          color: palette.textSecondary,
          fontSize: 14,
          height: 1.45,
        ),
      ),
    ];
  }

  List<Widget> _bodySlivers() {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    return [
      DeleteAccountConsequenceList(
        key: const ValueKey('delete-account-consequences'),
        items: deleteAccountConsequences(copy),
      ),
      const SizedBox(height: 20),
      // The page background is a DecoratedBox, and ListTile paints its ink on
      // the nearest Material — without this the splash lands behind it.
      Material(
        type: MaterialType.transparency,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: const ValueKey('delete-account-retained'),
            initiallyExpanded: _retainedOpen,
            onExpansionChanged: (open) => setState(() => _retainedOpen = open),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(top: 4, bottom: 8),
            title: Text(
              copy.text('What we keep, and why', 'Co zachowujemy i dlaczego'),
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            children: [
              DeleteAccountConsequenceList(
                items: deleteAccountRetentions(copy),
                danger: false,
              ),
              const SizedBox(height: 12),
              Text(
                copy.text(
                  'We cannot export your data for you yet — ask us by email and '
                      'we will prepare it by hand.',
                  'Nie możemy jeszcze wyeksportować Twoich danych automatycznie — '
                      'poproś nas e-mailem, a przygotujemy je ręcznie.',
                ),
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 13.5,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          key: const ValueKey('delete-account-web-link'),
          onPressed: () => _openUrl(deleteAccountWebUrl),
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
          label: Text(copy.text('Read this online', 'Przeczytaj to online')),
        ),
      ),
    ];
  }

  List<Widget> _actionSlivers() {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final error = _error;
    final working = _stage == _Stage.working;
    return [
      if (error != null) ...[
        Container(
          key: const ValueKey('delete-account-error'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: palette.dangerSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.error.withValues(alpha: .4)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline_rounded, size: 20, color: colors.error),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  error,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 13.5,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
      FilledButton.icon(
        key: const ValueKey('delete-account-primary'),
        style: FilledButton.styleFrom(
          backgroundColor: colors.errorContainer,
          foregroundColor: colors.onErrorContainer,
          minimumSize: const Size.fromHeight(52),
        ),
        onPressed: working ? null : _beginDeletion,
        icon: working
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.onErrorContainer,
                ),
              )
            : const Icon(Icons.delete_forever_rounded),
        label: Text(
          working
              ? copy.text('Working…', 'Przetwarzanie…')
              : copy.text(
                  'Delete my account permanently',
                  'Trwale usuń moje konto',
                ),
          textAlign: TextAlign.center,
        ),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        key: const ValueKey('delete-account-email-fallback'),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        onPressed: working
            ? null
            : () => _openUrl(
                'mailto:$deleteAccountMailbox'
                '?subject=Delete%20my%20YO%20Voice%20account',
              ),
        icon: const Icon(Icons.mail_outline_rounded, size: 18),
        label: Text(
          copy.text('Ask us by email instead', 'Poproś nas o to e-mailem'),
          textAlign: TextAlign.center,
        ),
      ),
    ];
  }
}

/// The password challenge.
///
/// It owns its controller rather than taking one from the caller: a controller
/// disposed the moment `showDialog` completes is still being read by the
/// field while the dialog animates out, which throws.
class _PasswordPromptDialog extends StatefulWidget {
  const _PasswordPromptDialog();

  @override
  State<_PasswordPromptDialog> createState() => _PasswordPromptDialogState();
}

class _PasswordPromptDialogState extends State<_PasswordPromptDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return AlertDialog(
      key: const ValueKey('delete-account-password-dialog'),
      title: Text(copy.text('Confirm it is you', 'Potwierdź, że to Ty')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: TextField(
          key: const ValueKey('delete-account-password-field'),
          controller: _controller,
          autofocus: true,
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          decoration: InputDecoration(
            labelText: copy.text('Password', 'Hasło'),
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(copy.text('Cancel', 'Anuluj')),
        ),
        FilledButton(
          key: const ValueKey('delete-account-password-submit'),
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(copy.text('Continue', 'Dalej')),
        ),
      ],
    );
  }
}

/// The last step: a typed confirmation, so the destructive control can never
/// be reached by a stray tap. Cancel holds initial focus on purpose.
class _ConfirmDeletionDialog extends StatefulWidget {
  const _ConfirmDeletionDialog({required this.word});

  final String word;

  @override
  State<_ConfirmDeletionDialog> createState() => _ConfirmDeletionDialogState();
}

class _ConfirmDeletionDialogState extends State<_ConfirmDeletionDialog> {
  final _controller = TextEditingController();
  bool _matches = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final matches =
          _controller.text.trim().toUpperCase() == widget.word.toUpperCase();
      if (matches != _matches) setState(() => _matches = matches);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      key: const ValueKey('delete-account-confirm-dialog'),
      title: Text(
        copy.text('Delete my account permanently', 'Trwale usuń moje konto'),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                copy.template(
                  'Type {word} to confirm. This cannot be undone.',
                  'Wpisz {word}, aby potwierdzić. Tej operacji nie można cofnąć.',
                  values: {'word': widget.word},
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('delete-account-confirm-field'),
                controller: _controller,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(labelText: widget.word),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('delete-account-confirm-cancel'),
          autofocus: true,
          onPressed: () => Navigator.pop(context, false),
          child: Text(copy.text('Cancel', 'Anuluj')),
        ),
        FilledButton(
          key: const ValueKey('delete-account-confirm-submit'),
          style: FilledButton.styleFrom(
            backgroundColor: colors.errorContainer,
            foregroundColor: colors.onErrorContainer,
          ),
          onPressed: _matches ? () => Navigator.pop(context, true) : null,
          child: Text(copy.text('Delete', 'Usuń')),
        ),
      ],
    );
  }
}

/// The terminal state. The request was accepted; the teardown runs on the
/// server, so the honest word is "being deleted", not "deleted".
///
/// AND THE SESSION IS STILL OPEN WHILE THIS PANEL IS ON SCREEN. Sign-out is
/// `onDone`, i.e. it happens when the person taps Done — the panel would
/// otherwise be torn out from under them by the auth listener the moment they
/// could read it, which is why the design sequences it after the tap. The copy
/// below therefore says what Done will do; it must never say sign-out has
/// already happened, because at this point it has not.
class _RequestedPanel extends StatelessWidget {
  const _RequestedPanel({required this.onDone});

  final Future<void> Function() onDone;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            key: const ValueKey('delete-account-pending'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.hourglass_top_rounded,
                size: 44,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(height: 18),
              Semantics(
                header: true,
                child: Text(
                  copy.text(
                    'Your account is being deleted',
                    'Twoje konto jest usuwane',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    height: 1.25,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                copy.text(
                  'This usually finishes within a few minutes. Tap Done to '
                      'sign out on this device.',
                  'Zwykle kończy się to w ciągu kilku minut. Naciśnij Gotowe, '
                      'aby wylogować się na tym urządzeniu.',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 26),
              FilledButton(
                key: const ValueKey('delete-account-done'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
                onPressed: onDone,
                child: Text(copy.text('Done', 'Gotowe')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
