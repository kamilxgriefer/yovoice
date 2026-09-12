import 'package:flutter/material.dart';
import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/shared/widgets/inputs/yo_keyboard_done_bar.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';

import '../../data/models/server_channel.dart';
import '../../data/models/server_creation.dart';
import '../../data/models/server_template.dart';
import '../../data/models/server_type.dart';
import '../../data/services/server_service.dart';
import '../server_localized_copy.dart';
import '../theme/server_identity.dart';
import '../widgets/server_template_selector.dart';
import '../widgets/server_type_symbol.dart';
import 'server_workspace_screen.dart';

class CreateServerScreen extends StatefulWidget {
  const CreateServerScreen({
    this.repository,
    this.initialType,
    this.onCreated,
    this.isRootTab = false,
    super.key,
  });
  final ServerRepository? repository;
  final ServerType? initialType;
  final ValueChanged<ServerCreationResult>? onCreated;
  final bool isRootTab;

  @override
  State<CreateServerScreen> createState() => _CreateServerScreenState();
}

class _CreateServerScreenState extends State<CreateServerScreen> {
  late final ServerRepository _repository;
  final _form = GlobalKey<FormState>();

  /// Anchors whichever outcome the last submit produced — the refusal notice
  /// or the error. Both render at the end of a scrolling form, so without
  /// this the only visible answer to a tap is the button changing its own
  /// label: the reason sits below the fold and nothing says to look for it.
  final _outcome = GlobalKey(debugLabel: 'server-create-outcome');
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _descriptionFocus = FocusNode();
  final _privacyByType = <ServerType, ServerPrivacy?>{};
  ServerType? _type;

  /// The language the server's seeded channel names are written in.
  ///
  /// It starts from the app's own locale rather than a hardcoded `English`:
  /// a Polish surface previewing `general / memes / Lounge` — and creating a
  /// server whose channels diverge from every board in the product — is a
  /// wrong default, not a choice. [_languageChosen] records that the person
  /// (or a resumed submission) has settled it, so a later locale rebuild
  /// never overwrites their pick.
  String _language = 'English';
  bool _languageChosen = false;
  ServerCreationRequest? _submission;
  Object? _error;
  bool _busy = false;
  bool _completed = false;

  /// True while the durable store is being asked whether this owner already
  /// has an unresolved submission for the chosen template.
  bool _restoring = false;

  /// True when [_submission] was resumed from the durable store rather than
  /// created on this screen, until the first attempt from here answers.
  bool _resumed = false;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? ServerService();
    _setType(widget.initialType);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_languageChosen) return;
    // `server_template.dart` carries a Polish name for every seed, and
    // `serverSeedsInPolish` is what decides which one is written.
    _language = Localizations.localeOf(context).languageCode == 'pl'
        ? 'Polish'
        : 'English';
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _descriptionFocus.dispose();
    super.dispose();
  }

  ServerPrivacy? _privacy(ServerType type) => _privacyByType.containsKey(type)
      ? _privacyByType[type]
      : type.requiresPrivacyChoice
      ? null
      : ServerPrivacy.inviteOnly;

  void _setType(ServerType? type) {
    _type = type;
    // A refusal answers one submission on one template. Leaving that form —
    // back to the selector, or on to another template — must not carry its
    // panel to a form nobody has submitted; if the new template has its own
    // unresolved record, the store read below restores that one instead.
    _error = null;
    _resumed = false;
    if (type != null) _restorePending(type);
  }

  /// Resumes an unresolved submission for this owner and template.
  ///
  /// The idempotency promise ("sending again will not create a second
  /// server") is only true if the *same* `requestId` and payload are what get
  /// resent — so a pending record found in the store takes over the form:
  /// its values are shown, its fields are locked and the action becomes
  /// "send again". Nothing is offered that would rotate the identity.
  Future<void> _restorePending(ServerType type) async {
    _restoring = true;
    ServerCreationRequest? pending;
    try {
      pending = await _repository.pendingCreation(type);
    } catch (_) {
      // A store that cannot be read is treated as empty: the in-memory
      // request still keeps one identity for as long as this screen lives.
      pending = null;
    }
    if (!mounted || _type != type) return;
    setState(() {
      _restoring = false;
      if (pending == null || _submission != null || _busy) return;
      _applySubmission(pending);
      _resumed = true;
      _error = null;
    });
  }

  void _applySubmission(ServerCreationRequest request) {
    _submission = request;
    _name.text = request.name;
    _description.text = request.description;
    _privacyByType[request.serverType] = request.privacy;
    _language = request.defaultLanguage;
    // A resumed request already carries the language it will send.
    _languageChosen = true;
  }

  Future<void> _forget(ServerCreationRequest request) async {
    try {
      await _repository.forgetPendingCreation(request);
    } catch (_) {
      // Failing to clear a resolved record only costs a redundant resend
      // later, which the backend answers idempotently.
    }
  }

  Future<void> _submit() async {
    if (_busy || _completed || _restoring || _type == null) return;
    var submission = _submission;
    if (submission == null) {
      if (!_form.currentState!.validate()) return;
      final type = _type!;
      final candidate = ServerCreationRequest(
        requestId: _repository.newRequestId(),
        serverType: type,
        name: _name.text.trim(),
        description: _description.text.trim(),
        privacy: _privacy(type)!,
        defaultLanguage: _language,
      );
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() {
        _busy = true;
        _error = null;
      });
      // Committed before the network write, so the identity survives the
      // screen, the shell's content slot and the process.
      try {
        submission = await _repository.rememberPendingCreation(candidate);
      } catch (_) {
        // Durable storage is a safety net, not a gate.
        submission = candidate;
      }
      if (!mounted) return;
      if (identical(submission, candidate)) {
        _submission = candidate;
      } else {
        // An older unresolved request for this scope wins: its id may
        // already have created a server, so the form shows what it sends.
        _applySubmission(submission);
      }
    } else {
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() {
        _busy = true;
        _error = null;
      });
    }
    try {
      final result = await _repository.createServer(submission);
      await _forget(submission);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _completed = true;
        _resumed = false;
      });
      final onCreated = widget.onCreated;
      if (onCreated != null) {
        onCreated(result);
      } else {
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => ServerWorkspaceScreen(
              serverId: result.serverId,
              initialChannelId: result.defaultChannelId,
              repository: _repository,
              // The server exists now, so the next honest thing to offer is
              // the people who belong in it.
              justCreated: true,
            ),
          ),
        );
      }
    } catch (error) {
      final failure = classifyServerCreationFailure(error);
      // A refusal that happened before any write has answered for this id
      // for good; only an uncertain outcome keeps the record resumable.
      if (failure.resolvesRequest) await _forget(submission);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error;
        _resumed = false;
        // `invalid-argument` is the one refusal editing can fix. The payload
        // was never committed, so a corrected one is a new request with a
        // fresh id — the old id is discarded, not reused with new contents.
        if (failure.isCorrectable) _submission = null;
      });
      _revealOutcome();
    }
  }

  /// Brings the refusal or the error into view after the frame that built it.
  ///
  /// The outcome renders at the end of the form, so on a phone a submit that
  /// fails changes only the action bar — the sentence explaining why is off
  /// screen, and nothing suggests scrolling for it.
  void _revealOutcome() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final anchor = _outcome.currentContext;
      if (anchor == null) return;
      // No scrollable ancestor on a viewport tall enough to show everything.
      if (Scrollable.maybeOf(anchor) == null) return;
      Scrollable.ensureVisible(
        anchor,
        alignment: 0.5,
        duration: AppMotion.resolve(context, AppMotion.quick),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final type = _type;
    return PopScope(
      canPop: !_busy && (type == null || _submission != null),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_busy && _submission == null && type != null) {
          setState(() => _setType(null));
        }
      },
      child: Scaffold(
        backgroundColor: palette.background,
        appBar: widget.isRootTab
            ? null
            : AppBar(
                title: Text(
                  type == null
                      ? 'YO Voice'
                      : copy.text('Your server', 'Twój serwer'),
                ),
                leading: IconButton(
                  tooltip: copy.text('Back', 'Wstecz'),
                  onPressed: _busy
                      ? null
                      : () {
                          if (type != null && _submission == null) {
                            setState(() => _setType(null));
                          } else {
                            Navigator.of(context).maybePop();
                          }
                        },
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  icon: const BackButtonIcon(),
                ),
              ),
        body: SafeArea(
          top: widget.isRootTab,
          child: type == null
              ? ServerTemplateSelector(
                  onSelected: (selected) => setState(() => _setType(selected)),
                )
              : _restoring
              // A store read takes milliseconds; the form is not shown
              // until it answers so a pending request can never be typed
              // over, and so the dropdowns' initial values are the resumed
              // ones the first time they are built.
              ? const SizedBox.expand(key: ValueKey('server-create-restoring'))
              : _configuration(context, type),
        ),
      ),
    );
  }

  Widget _configuration(BuildContext context, ServerType type) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final identity = ServerIdentity.of(
      type,
    ).resolve(Theme.of(context).brightness);
    // Locked from the FIRST busy frame, not from the moment the durable
    // request record has answered: the store write sits behind an await, so
    // `_submission` is still null for a frame or a slow disk while the tap has
    // already been accepted. A field that unlocks in that window can change
    // the payload the resumed identity will send (re-review R-7).
    final locked = _busy || _submission != null;
    final error = _error;
    final failure = error == null ? null : classifyServerCreationFailure(error);
    // A failure that resending cannot fix must not offer a button that only
    // fails again; a refused payload unlocks instead so it can be corrected;
    // everything else keeps the identical request available.
    final canSubmit =
        !_busy &&
        !_completed &&
        (failure == null || failure.isRetryable || failure.isCorrectable);
    final submitButton = FilledButton(
      key: const ValueKey('server-create-submit'),
      onPressed: canSubmit ? _submit : null,
      style: FilledButton.styleFrom(
        backgroundColor: identity.cta,
        foregroundColor: identity.onCta,
        minimumSize: const Size.fromHeight(52),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ).copyWith(side: serverFocusRing(identity.onCta)),
      child: _busy
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: palette.textSecondary,
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(child: Text(copy.serverCreating)),
              ],
            )
          : Text(switch (failure) {
              null => _resumed ? copy.serverResend : copy.serverCreateAction,
              // The gate can only be opened server-side, so the honest action
              // is to look again rather than to "try" the same dead endpoint.
              ServerCreationFailure.unavailable => copy.serverCheckAgain,
              ServerCreationFailure.offline => copy.serverResend,
              ServerCreationFailure.unknown => copy.serverTryAgain,
              // Unlocked for correction: the next tap is a new submission.
              ServerCreationFailure.rejected => copy.serverCreateAction,
              // Disarmed; the message names the real next step.
              ServerCreationFailure.capacityReached ||
              ServerCreationFailure.signedOut ||
              ServerCreationFailure.precondition ||
              ServerCreationFailure.denied ||
              ServerCreationFailure.lost => copy.serverCreateAction,
            }),
    );
    final header = Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 8,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ServerTypeSymbol(type: type, color: identity.foreground),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                copy.serverTypeTitle(type),
                style: AppTypography.headlineMedium.copyWith(
                  color: palette.textPrimary,
                ),
              ),
            ),
          ],
        ),
        TextButton(
          onPressed: locked ? null : () => setState(() => _setType(null)),
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          child: Text(copy.text('Change template', 'Zmień szablon')),
        ),
      ],
    );
    final preview = _SeededChannelPreview(
      type: type,
      defaultLanguage: _language,
      identity: identity,
    );
    final startingPoint = _StartingPointCard(type: type);
    final allowance = Text(
      // FREE_SERVER_LIMIT is 20 for four templates; a family server is
      // charged to `familyFreeV1`, one per owner, and never to that 20.
      type == ServerType.family
          ? copy.serverCreationFamilyAllowanceBody
          : copy.serverCreationAllowanceBody,
      key: const ValueKey('server-create-allowance'),
      style: AppTypography.bodySmall.copyWith(color: palette.textSecondary),
    );

    List<Widget> formChildren({required bool withAside}) => [
      header,
      const SizedBox(height: AppRhythm.tight),
      Text(
        copy.serverTypeDescription(type),
        style: AppTypography.bodyMedium.copyWith(color: palette.textSecondary),
      ),
      const SizedBox(height: AppRhythm.section),
      TextFormField(
        key: const ValueKey('server-name'),
        controller: _name,
        enabled: !locked,
        maxLength: 40,
        textInputAction: TextInputAction.next,
        onFieldSubmitted: (_) => _descriptionFocus.requestFocus(),
        decoration: InputDecoration(
          labelText: copy.text('Server name', 'Nazwa serwera'),
        ),
        validator: (value) =>
            (value?.trim().length ?? 0) < 3 || (value?.trim().length ?? 0) > 40
            ? copy.text('Use 3–40 characters.', 'Użyj od 3 do 40 znaków.')
            : null,
      ),
      const SizedBox(height: AppRhythm.title),
      _IconSection(name: _name, identity: identity),
      const SizedBox(height: AppRhythm.title),
      TextFormField(
        key: const ValueKey('server-description'),
        controller: _description,
        focusNode: _descriptionFocus,
        enabled: !locked,
        minLines: 3,
        maxLines: 6,
        maxLength: 220,
        textInputAction: TextInputAction.newline,
        decoration: InputDecoration(
          labelText: copy.text('Description (optional)', 'Opis (opcjonalnie)'),
        ),
        validator: (value) => (value?.trim().length ?? 0) > 220
            ? copy.text(
                'Use up to 220 characters.',
                'Użyj maksymalnie 220 znaków.',
              )
            : null,
      ),
      const SizedBox(height: AppRhythm.title),
      DropdownButtonFormField<ServerPrivacy>(
        key: ValueKey('server-privacy-${type.name}'),
        initialValue: _privacy(type),
        isExpanded: true,
        decoration: InputDecoration(
          labelText: copy.text('Privacy', 'Prywatność'),
        ),
        hint: Text(
          copy.text('Choose who can join', 'Wybierz, kto może dołączyć'),
        ),
        items: [
          for (final privacy in ServerPrivacy.values)
            if ((type != ServerType.family ||
                    privacy == ServerPrivacy.inviteOnly) &&
                (type.allowsPublic || privacy != ServerPrivacy.public))
              DropdownMenuItem(
                value: privacy,
                child: Text(copy.serverPrivacyTitle(privacy)),
              ),
        ],
        onChanged: locked || type == ServerType.family
            ? null
            : (value) => setState(() => _privacyByType[type] = value),
        validator: (value) => value == null
            ? copy.text(
                'Choose privacy before creating your server.',
                'Wybierz prywatność przed utworzeniem serwera.',
              )
            : null,
      ),
      if (_privacy(type) case final privacy?) ...[
        const SizedBox(height: AppRhythm.tight),
        Text(
          copy.serverPrivacyDescription(privacy),
          style: AppTypography.bodySmall.copyWith(color: palette.textSecondary),
        ),
      ],
      const SizedBox(height: AppRhythm.section),
      DropdownButtonFormField<String>(
        key: const ValueKey('server-language'),
        initialValue: _language,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: copy.text('Server language', 'Język serwera'),
        ),
        items: [
          DropdownMenuItem(value: 'English', child: Text(copy.english)),
          DropdownMenuItem(value: 'Polish', child: Text(copy.polish)),
        ],
        onChanged: locked
            ? null
            : (value) => setState(() {
                _language = value!;
                _languageChosen = true;
              }),
      ),
      if (!withAside) ...[
        const SizedBox(height: AppRhythm.section),
        preview,
        const SizedBox(height: AppRhythm.section),
        startingPoint,
      ],
      const SizedBox(height: AppRhythm.title),
      allowance,
      if (_resumed && failure == null) ...[
        const SizedBox(height: AppRhythm.title),
        Semantics(
          liveRegion: true,
          child: Container(
            key: const ValueKey('server-create-resumed'),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: palette.infoSurface,
              borderRadius: AppRadius.md,
              border: Border.all(color: palette.border),
            ),
            child: Text(
              copy.serverCreationResumedBody,
              style: AppTypography.bodyMedium.copyWith(
                color: palette.textPrimary,
              ),
            ),
          ),
        ),
      ],
      if (failure != null) ...[
        const SizedBox(height: AppRhythm.title),
        if (failure.isBackendMissing)
          // The same live region the error path already had: a refusal is an
          // answer to the tap, so it is announced rather than merely drawn.
          Semantics(
            liveRegion: true,
            child: KeyedSubtree(
              key: _outcome,
              child: const _UnavailableNotice(),
            ),
          )
        else ...[
          Semantics(
            liveRegion: true,
            child: KeyedSubtree(
              key: _outcome,
              child: Container(
                key: const ValueKey('server-create-error'),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: palette.dangerSurface,
                  borderRadius: AppRadius.md,
                ),
                child: Text(
                  _failureMessage(failure, error!, type, copy),
                  style: AppTypography.bodyMedium.copyWith(
                    color: palette.dangerForeground,
                  ),
                ),
              ),
            ),
          ),
          if (failure.isRetryable || failure.isCorrectable) ...[
            const SizedBox(height: AppRhythm.tight),
            Text(
              copy.serverCreationRetrySafe,
              style: AppTypography.bodySmall.copyWith(
                color: palette.textSecondary,
              ),
            ),
          ],
        ],
      ],
      const SizedBox(height: AppRhythm.page),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Scaffold removes the body's inherited inset. The view remains the
        // keyboard authority inside a shell, and the resized body re-lays out
        // this builder without replacing the focused form or its controllers.
        final keyboardOpen =
            MediaQuery.viewInsetsOf(context).bottom > 0 ||
            (View.maybeOf(context)?.viewInsets.bottom ?? 0) > 0;
        final wide =
            constraints.maxWidth >= ServerConfigurationMetrics.wideBreakpoint;
        const frameWidth =
            ServerConfigurationMetrics.formColumnWidth +
            ServerConfigurationMetrics.gutter +
            ServerConfigurationMetrics.asideWidth +
            2 * AppSpacing.lg;
        final Widget body;
        final Widget actionBar;
        if (wide) {
          // Desktop: the form beside the seeded-channel preview. Each column
          // scrolls on its own, so the preview — the part people re-read
          // while they type — stays in view instead of being scrolled past.
          // Centred horizontally only: on a tall viewport the frame starts
          // where the one-column form starts, it never floats to the middle.
          body = Align(
            alignment: AlignmentDirectional.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: frameWidth),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      key: const ValueKey('server-create-form-scroll'),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        AppSpacing.lg,
                        AppSpacing.lg,
                        0,
                        AppSpacing.lg,
                      ),
                      child: Form(
                        key: _form,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ...formChildren(withAside: true),
                            if (keyboardOpen) submitButton,
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: ServerConfigurationMetrics.gutter),
                  // The aside carries the frame's end padding itself, so the
                  // preview is exactly [asideWidth] and the form column gets
                  // exactly [formColumnWidth] of the 1060 px frame.
                  SizedBox(
                    width:
                        ServerConfigurationMetrics.asideWidth + AppSpacing.lg,
                    child: SingleChildScrollView(
                      key: const ValueKey('server-create-aside-scroll'),
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        0,
                        AppSpacing.lg,
                        AppSpacing.lg,
                        AppSpacing.lg,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          preview,
                          const SizedBox(height: AppRhythm.section),
                          startingPoint,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
          actionBar = Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: frameWidth),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                child: submitButton,
              ),
            ),
          );
        } else {
          // Narrow and medium: one column, the preview under the fields.
          body = SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: ResponsiveContentFrame(
              width: ResponsiveContentWidth.form,
              fillHeight: false,
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ...formChildren(withAside: false),
                    if (keyboardOpen) submitButton,
                  ],
                ),
              ),
            ),
          );
          actionBar = ResponsiveContentFrame(
            width: ResponsiveContentWidth.form,
            fillHeight: false,
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
            child: submitButton,
          );
        }
        return Column(
          children: [
            Expanded(child: body),
            const YoKeyboardDoneBar(),
            if (!keyboardOpen)
              Material(color: palette.surface, child: actionBar),
          ],
        );
      },
    );
  }

  String _failureMessage(
    ServerCreationFailure failure,
    Object error,
    ServerType type,
    AppLocalizations copy,
  ) => switch (failure) {
    ServerCreationFailure.offline => copy.serverCreationOfflineBody,
    ServerCreationFailure.capacityReached => copy.serverCreationCapacityBody,
    ServerCreationFailure.rejected => copy.serverCreationRejectedBody,
    ServerCreationFailure.precondition =>
      type == ServerType.family
          ? copy.serverCreationFamilyExistsBody
          : copy.serverCreationPreconditionBody,
    ServerCreationFailure.denied => copy.serverCreationDeniedBody,
    ServerCreationFailure.lost => copy.serverCreationLostBody,
    ServerCreationFailure.unavailable ||
    ServerCreationFailure.signedOut ||
    ServerCreationFailure.unknown => friendlyErrorMessage(error, copy: copy),
  };
}

/// The truthful state when `createServerV1` is not registered.
///
/// It is deliberately not a red error: nothing failed and nothing was lost —
/// the endpoint this build calls does not exist in this environment yet
/// (ADR-176). Saying "something went wrong, try again" would be a lie that
/// sends people around a loop that cannot close.
class _UnavailableNotice extends StatelessWidget {
  const _UnavailableNotice();

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const ValueKey('server-create-unavailable'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: palette.infoSurface,
          borderRadius: AppRadius.md,
          border: Border.all(color: palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.schedule_rounded,
                  size: 20,
                  color: palette.infoForeground,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    copy.serverCreationUnavailableTitle,
                    style: AppTypography.titleSmall.copyWith(
                      color: palette.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              copy.serverCreationUnavailableBody,
              style: AppTypography.bodyMedium.copyWith(
                color: palette.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            Chip(
              label: Text(copy.serverComingSoon),
              avatar: const Icon(Icons.schedule_rounded, size: 16),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the template gives a person to shape, and the one promise the
/// configuration step makes about media: none of it is switched on.
class _StartingPointCard extends StatelessWidget {
  const _StartingPointCard({required this.type});
  final ServerType type;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    return Container(
      key: const ValueKey('server-create-starting-point'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadius.lg,
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            copy.text(
              'A starting point you can shape',
              'Początek, który dopasujesz do siebie',
            ),
            style: AppTypography.titleMedium.copyWith(
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            copy.serverTypeFeatures(type),
            style: AppTypography.bodyMedium.copyWith(
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            copy.text(
              'Your server starts with you. Microphone and camera stay off.',
              'Serwer zaczyna się od Ciebie. Mikrofon i kamera pozostają wyłączone.',
            ),
            style: AppTypography.bodySmall.copyWith(
              color: palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// The server's icon before the server exists.
///
/// There is no V1 artwork writer — `createServerV1` writes `avatarUrl: null`
/// and no upload reservation exists — so the only honest icon today is the
/// identity tile the workspace already renders. It previews live from the
/// name field; uploading a picture is shown disabled rather than offered.
class _IconSection extends StatelessWidget {
  const _IconSection({required this.name, required this.identity});
  final TextEditingController name;
  final ServerIdentityVisuals identity;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: name,
              builder: (context, value, _) {
                final trimmed = value.text.trim();
                return Container(
                  key: const ValueKey('server-icon-preview'),
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: identity.iconSurface,
                    borderRadius: AppRadius.lg,
                    border: Border.all(color: identity.iconBorder),
                  ),
                  child: Center(
                    child: FittedBox(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          trimmed.isEmpty
                              ? 'YO'
                              : trimmed.characters.first.toUpperCase(),
                          style: AppTypography.headlineMedium.copyWith(
                            color: identity.foreground,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    copy.serverIconTitle,
                    style: AppTypography.titleSmall.copyWith(
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    copy.serverIconBody,
                    style: AppTypography.bodySmall.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppRhythm.item),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            key: const ValueKey('server-icon-upload'),
            onPressed: null,
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
            label: Text('${copy.serverIconUpload} · ${copy.serverComingSoon}'),
          ),
        ),
      ],
    );
  }
}

/// What the server will actually be seeded with, before it is created.
///
/// Every row comes from the Dart mirror of the server-owned template table,
/// including the language the server itself will apply and the two restricted
/// company channels. Nothing here is aspirational: if a row is shown, the
/// reviewed `createServerV1` transaction writes it.
class _SeededChannelPreview extends StatelessWidget {
  const _SeededChannelPreview({
    required this.type,
    required this.defaultLanguage,
    required this.identity,
  });
  final ServerType type;
  final String defaultLanguage;
  final ServerIdentityVisuals identity;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final seeds = serverTemplateChannelsFor(type);
    // Fixed group order, server order within each group. Owner-defined
    // categories have no callable and no Rules yet, so grouping is derived
    // from the channel kind rather than invented.
    const groupOrder = <ServerChannelKind>[
      ServerChannelKind.text,
      ServerChannelKind.voice,
      ServerChannelKind.events,
    ];
    return Container(
      key: const ValueKey('server-seeded-channels'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadius.lg,
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            copy.serverSeededChannelsTitle,
            style: AppTypography.titleMedium.copyWith(
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            copy.serverSeededChannelsBody,
            style: AppTypography.bodySmall.copyWith(
              color: palette.textSecondary,
            ),
          ),
          for (final group in groupOrder)
            if (seeds.where((seed) => _groupOf(seed.kind) == group).toList()
                case final rows when rows.isNotEmpty) ...[
              const SizedBox(height: AppRhythm.title),
              Text(
                copy.serverChannelGroup(group),
                style: AppTypography.labelSmall.copyWith(
                  color: palette.textTertiary,
                  letterSpacing: 1.2,
                ),
              ),
              for (final seed in rows) ...[
                const SizedBox(height: AppRhythm.tight),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      seed.restricted
                          ? Icons.lock_outline
                          : serverChannelIcon(seed.kind),
                      size: 18,
                      color: seed.kind.isMedia
                          ? identity.foreground
                          : palette.textSecondary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        seed.nameFor(defaultLanguage),
                        style: AppTypography.bodyMedium.copyWith(
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                    if (seed.restricted) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          copy.serverChannelRestricted,
                          textAlign: TextAlign.end,
                          style: AppTypography.bodySmall.copyWith(
                            color: palette.textTertiary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
        ],
      ),
    );
  }

  /// Collapses the fourteen channel kinds onto the three headings the
  /// reference panels use, keyed by a representative kind.
  static ServerChannelKind _groupOf(ServerChannelKind kind) => switch (kind) {
    ServerChannelKind.voice ||
    ServerChannelKind.stage ||
    ServerChannelKind.meeting => ServerChannelKind.voice,
    ServerChannelKind.text ||
    ServerChannelKind.announcements => ServerChannelKind.text,
    _ => ServerChannelKind.events,
  };
}
