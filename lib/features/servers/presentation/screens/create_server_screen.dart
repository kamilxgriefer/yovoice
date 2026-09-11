import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/shared/widgets/inputs/yo_keyboard_done_bar.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';

import '../../data/models/server_creation.dart';
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
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _descriptionFocus = FocusNode();
  final _privacyByType = <ServerType, ServerPrivacy?>{};
  ServerType? _type;
  String _language = 'English';
  ServerCreationRequest? _submission;
  Object? _error;
  bool _busy = false;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? ServerService();
    _type = widget.initialType;
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

  Future<void> _submit() async {
    if (_busy || _completed || _type == null) return;
    if (_submission == null) {
      if (!_form.currentState!.validate()) return;
      final type = _type!;
      _submission = ServerCreationRequest(
        requestId: _repository.newRequestId(),
        serverType: type,
        name: _name.text.trim(),
        description: _description.text.trim(),
        privacy: _privacy(type)!,
        defaultLanguage: _language,
      );
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _repository.createServer(_submission!);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _completed = true;
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
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error;
        });
      }
    }
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
          setState(() => _type = null);
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
                            setState(() => _type = null);
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
                  onSelected: (selected) => setState(() => _type = selected),
                )
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
    final locked = _submission != null;
    final error = _error;
    final submitButton = FilledButton(
      key: const ValueKey('server-create-submit'),
      onPressed: _busy || _completed ? null : _submit,
      style: FilledButton.styleFrom(
        backgroundColor: identity.cta,
        foregroundColor: identity.onCta,
        minimumSize: const Size.fromHeight(52),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
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
                Flexible(child: Text(copy.text('Creating…', 'Tworzenie…'))),
              ],
            )
          : Text(
              error == null
                  ? copy.text('Create server', 'Stwórz serwer')
                  : copy.text('Try again', 'Spróbuj ponownie'),
            ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // Scaffold removes the body's inherited inset. The view remains the
        // keyboard authority inside a shell, and the resized body re-lays out
        // this builder without replacing the focused form or its controllers.
        final keyboardOpen =
            MediaQuery.viewInsetsOf(context).bottom > 0 ||
            (View.maybeOf(context)?.viewInsets.bottom ?? 0) > 0;
        return Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: ResponsiveContentFrame(
                  width: ResponsiveContentWidth.form,
                  fillHeight: false,
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 16,
                          runSpacing: 8,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ServerTypeSymbol(
                                  type: type,
                                  color: identity.foreground,
                                ),
                                const SizedBox(width: 12),
                                Flexible(
                                  child: Text(
                                    copy.serverTypeTitle(type),
                                    style: AppTypography.headlineMedium
                                        .copyWith(color: palette.textPrimary),
                                  ),
                                ),
                              ],
                            ),
                            TextButton(
                              onPressed: locked
                                  ? null
                                  : () => setState(() => _type = null),
                              style: TextButton.styleFrom(
                                minimumSize: const Size(48, 48),
                              ),
                              child: Text(
                                copy.text('Change template', 'Zmień szablon'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppRhythm.tight),
                        Text(
                          copy.serverTypeDescription(type),
                          style: AppTypography.bodyMedium.copyWith(
                            color: palette.textSecondary,
                          ),
                        ),
                        const SizedBox(height: AppRhythm.section),
                        TextFormField(
                          key: const ValueKey('server-name'),
                          controller: _name,
                          enabled: !locked,
                          maxLength: 40,
                          textInputAction: TextInputAction.next,
                          onFieldSubmitted: (_) =>
                              _descriptionFocus.requestFocus(),
                          decoration: InputDecoration(
                            labelText: copy.text(
                              'Server name',
                              'Nazwa serwera',
                            ),
                          ),
                          validator: (value) =>
                              (value?.trim().length ?? 0) < 3 ||
                                  (value?.trim().length ?? 0) > 40
                              ? copy.text(
                                  'Use 3–40 characters.',
                                  'Użyj od 3 do 40 znaków.',
                                )
                              : null,
                        ),
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
                            labelText: copy.text(
                              'Description (optional)',
                              'Opis (opcjonalnie)',
                            ),
                          ),
                          validator: (value) =>
                              (value?.trim().length ?? 0) > 220
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
                            copy.text(
                              'Choose who can join',
                              'Wybierz, kto może dołączyć',
                            ),
                          ),
                          items: [
                            for (final privacy in ServerPrivacy.values)
                              if ((type != ServerType.family ||
                                      privacy == ServerPrivacy.inviteOnly) &&
                                  (type.allowsPublic ||
                                      privacy != ServerPrivacy.public))
                                DropdownMenuItem(
                                  value: privacy,
                                  child: Text(copy.serverPrivacyTitle(privacy)),
                                ),
                          ],
                          onChanged: locked || type == ServerType.family
                              ? null
                              : (value) => setState(
                                  () => _privacyByType[type] = value,
                                ),
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
                            style: AppTypography.bodySmall.copyWith(
                              color: palette.textSecondary,
                            ),
                          ),
                        ],
                        const SizedBox(height: AppRhythm.section),
                        DropdownButtonFormField<String>(
                          key: const ValueKey('server-language'),
                          initialValue: _language,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: copy.text(
                              'Server language',
                              'Język serwera',
                            ),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: 'English',
                              child: Text(copy.english),
                            ),
                            DropdownMenuItem(
                              value: 'Polish',
                              child: Text(copy.polish),
                            ),
                          ],
                          onChanged: locked
                              ? null
                              : (value) => setState(() => _language = value!),
                        ),
                        const SizedBox(height: AppRhythm.section),
                        Container(
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
                        ),
                        const SizedBox(height: AppRhythm.title),
                        Text(
                          copy.text(
                            'Create up to 20 new servers for free.',
                            'Możesz utworzyć bezpłatnie do 20 nowych serwerów.',
                          ),
                          style: AppTypography.bodySmall.copyWith(
                            color: palette.textSecondary,
                          ),
                        ),
                        if (error != null) ...[
                          const SizedBox(height: AppRhythm.title),
                          Semantics(
                            liveRegion: true,
                            child: Container(
                              key: const ValueKey('server-create-error'),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: palette.dangerSurface,
                                borderRadius: AppRadius.md,
                              ),
                              child: Text(
                                _errorMessage(error, copy),
                                style: AppTypography.bodyMedium.copyWith(
                                  color: palette.dangerForeground,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: AppRhythm.tight),
                          Text(
                            copy.text(
                              'Your details are kept for a safe retry.',
                              'Twoje dane zostały zachowane do bezpiecznego ponowienia.',
                            ),
                            style: AppTypography.bodySmall.copyWith(
                              color: palette.textSecondary,
                            ),
                          ),
                        ],
                        const SizedBox(height: AppRhythm.page),
                        if (keyboardOpen) submitButton,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const YoKeyboardDoneBar(),
            if (!keyboardOpen)
              Material(
                color: palette.surface,
                child: ResponsiveContentFrame(
                  width: ResponsiveContentWidth.form,
                  fillHeight: false,
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                  child: submitButton,
                ),
              ),
          ],
        );
      },
    );
  }

  String _errorMessage(Object error, AppLocalizations copy) {
    if (error is FirebaseFunctionsException &&
        error.code == 'resource-exhausted') {
      final details = error.details;
      if (details is Map && details['reason'] == 'server-capacity-reached') {
        return copy.text(
          'You have reached the limit of 20 active servers.',
          'Masz już 20 aktywnych serwerów.',
        );
      }
    }
    return friendlyErrorMessage(error, copy: copy);
  }
}
