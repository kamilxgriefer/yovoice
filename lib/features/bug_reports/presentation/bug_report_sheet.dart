import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/features/bug_reports/data/bug_report_context.dart';
import 'package:yovoice/features/bug_reports/data/bug_report_service.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';

/// Below this width the reporter is a bottom sheet; at and above it, a
/// centred dialog no wider than [bugReportDialogMaxWidth].
const double bugReportDialogBreakpoint = 600;
const double bugReportDialogMaxWidth = 560;

/// Opens the reporter as a bottom sheet (narrow) or a dialog (medium/wide).
///
/// [screenshot] is the frame captured just before the reporter opened; it is
/// only a CANDIDATE. Nothing leaves the device unless the reporter opens the
/// preview and confirms it.
Future<void> showBugReportSheet(
  BuildContext context, {
  required Future<BugReportContext> Function() contextBuilder,
  Uint8List? screenshot,
  bool captureBlocked = false,
  BugReportService? service,
}) {
  final form = BugReportForm(
    contextBuilder: contextBuilder,
    screenshot: screenshot,
    captureBlocked: captureBlocked,
    service: service,
  );
  final width = MediaQuery.sizeOf(context).width;
  if (width < bugReportDialogBreakpoint) {
    final palette = context.appPalette;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: palette.surfaceRaised,
      constraints: ResponsiveContentFrame.adaptiveModalConstraints(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            YoModalSheetChrome(
              sheetLabel: AppLocalizations.of(
                sheetContext,
              ).text('Report a bug', 'Zgłoś błąd'),
              surfaceColor: palette.surfaceRaised,
              onClose: () => Navigator.of(sheetContext).pop(),
            ),
            Flexible(child: form),
          ],
        ),
      ),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: dialogContext.appPalette.surfaceRaised,
      insetPadding: const EdgeInsets.all(AppRhythm.section),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.lg),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: bugReportDialogMaxWidth,
          maxHeight: MediaQuery.sizeOf(dialogContext).height * .9,
        ),
        child: form,
      ),
    ),
  );
}

/// The reporter itself — shared by the sheet and the dialog.
class BugReportForm extends StatefulWidget {
  const BugReportForm({
    required this.contextBuilder,
    this.screenshot,
    this.captureBlocked = false,
    this.service,
    this.openPrivacyPolicy,
    super.key,
  });

  final Future<BugReportContext> Function() contextBuilder;
  final Uint8List? screenshot;
  final bool captureBlocked;
  final BugReportService? service;

  /// Injected by tests; production opens yovoice.app/privacy.
  final VoidCallback? openPrivacyPolicy;

  @override
  State<BugReportForm> createState() => _BugReportFormState();
}

enum _Phase { editing, sending, sent }

class _BugReportFormState extends State<BugReportForm> {
  final _description = TextEditingController();
  // One idempotency key per composed report: a retry after a lost answer
  // replays the same report instead of filing a second one.
  final String _requestId = BugReportService.newRequestId();
  late final BugReportService _service = widget.service ?? BugReportService();

  _Phase _phase = _Phase.editing;
  bool _screenshotConfirmed = false;
  bool _showLengthError = false;
  String? _errorCode;
  BugReportSubmission? _result;

  static const int _minLength = 10;
  static const int _maxLength = 2000;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _reviewScreenshot() async {
    final bytes = widget.screenshot;
    if (bytes == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _ScreenshotPreviewDialog(bytes: bytes),
    );
    if (!mounted) return;
    setState(() => _screenshotConfirmed = confirmed == true);
  }

  Future<void> _send() async {
    final description = _description.text.trim();
    if (description.length < _minLength) {
      setState(() => _showLengthError = true);
      return;
    }
    setState(() {
      _phase = _Phase.sending;
      _errorCode = null;
    });
    try {
      final reportContext = await widget.contextBuilder();
      final result = await _service.submit(
        requestId: _requestId,
        description: description,
        context: reportContext,
        screenshot: _screenshotConfirmed ? widget.screenshot : null,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _phase = _Phase.sent;
      });
    } on BugReportException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorCode = error.code;
        _phase = _Phase.editing;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorCode = 'network';
        _phase = _Phase.editing;
      });
    }
  }

  String _errorText(AppLocalizations copy, String code) => switch (code) {
    'resource-exhausted' => copy.text(
      'You have sent several reports in a short time. Try again a little later.',
      'Wysłano kilka zgłoszeń w krótkim czasie. Spróbuj ponownie za chwilę.',
    ),
    'failed-precondition' => copy.text(
      'Bug reports are paused right now. You can still email support@yovoice.app.',
      'Zgłoszenia błędów są teraz wstrzymane. Nadal możesz napisać na support@yovoice.app.',
    ),
    'unauthenticated' => copy.text(
      'Sign in to report a bug, or email support@yovoice.app.',
      'Zaloguj się, aby zgłosić błąd, lub napisz na support@yovoice.app.',
    ),
    'permission-denied' => copy.text(
      'This account cannot send bug reports. Email support@yovoice.app instead.',
      'To konto nie może wysyłać zgłoszeń. Napisz na support@yovoice.app.',
    ),
    _ => copy.text(
      'Your report could not be sent. Check your connection and try again, or email support@yovoice.app.',
      'Nie udało się wysłać zgłoszenia. Sprawdź połączenie i spróbuj ponownie lub napisz na support@yovoice.app.',
    ),
  };

  void _openPrivacy() {
    final override = widget.openPrivacyPolicy;
    if (override != null) {
      override();
      return;
    }
    unawaited(
      launchUrl(
        Uri.parse('https://yovoice.app/privacy'),
        mode: LaunchMode.externalApplication,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    if (_phase == _Phase.sent) return _sentView(context, copy);

    final sending = _phase == _Phase.sending;
    return SingleChildScrollView(
      key: const ValueKey('bug-report-form'),
      padding: const EdgeInsets.fromLTRB(
        AppRhythm.section,
        AppRhythm.tight,
        AppRhythm.section,
        AppRhythm.section,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.bug_report_rounded, color: colors.primary),
              const SizedBox(width: AppRhythm.tight),
              Expanded(
                child: Text(
                  copy.text('Report a bug', 'Zgłoś błąd'),
                  style: text.titleLarge?.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppRhythm.hairline),
          Text(
            copy.text(
              'Tell us what went wrong. It goes straight to the YO Voice team.',
              'Opisz, co poszło nie tak. Zgłoszenie trafi prosto do zespołu YO Voice.',
            ),
            style: text.bodyMedium?.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: AppRhythm.title),
          TextField(
            key: const ValueKey('bug-report-description'),
            controller: _description,
            enabled: !sending,
            minLines: 4,
            maxLines: 8,
            maxLength: _maxLength,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) {
              if (_showLengthError) setState(() => _showLengthError = false);
            },
            decoration: InputDecoration(
              labelText: copy.text('What happened?', 'Co się stało?'),
              hintText: copy.text(
                'What did you do, what did you expect, and what happened instead?',
                'Co robiłeś, czego się spodziewałeś i co się stało zamiast tego?',
              ),
              alignLabelWithHint: true,
              errorText: _showLengthError
                  ? copy.text(
                      'Describe the problem in at least 10 characters.',
                      'Opisz problem, używając co najmniej 10 znaków.',
                    )
                  : null,
            ),
          ),
          const SizedBox(height: AppRhythm.item),
          _screenshotSection(context, copy, sending),
          const SizedBox(height: AppRhythm.item),
          Text(
            copy.text(
              'Sent with your report: app version and build, platform, OS version, language, theme, the screen you were on and your account ID. Never your messages, unless they are visible in a screenshot you choose to attach.',
              'Razem ze zgłoszeniem wysyłamy: wersję i kompilację aplikacji, platformę, wersję systemu, język, motyw, ekran, na którym byłeś, oraz identyfikator konta. Nigdy Twoich wiadomości, chyba że widać je na zrzucie ekranu, który sam dołączysz.',
            ),
            style: text.bodySmall?.copyWith(color: palette.textTertiary),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              key: const ValueKey('bug-report-privacy-link'),
              onPressed: _openPrivacy,
              child: Text(copy.text('Privacy policy', 'Polityka prywatności')),
            ),
          ),
          if (_errorCode != null) ...[
            const SizedBox(height: AppRhythm.hairline),
            Container(
              key: const ValueKey('bug-report-error'),
              padding: const EdgeInsets.all(AppRhythm.item),
              decoration: BoxDecoration(
                color: palette.dangerSurface,
                borderRadius: AppRadius.card,
              ),
              child: Text(
                _errorText(copy, _errorCode!),
                style: text.bodyMedium?.copyWith(
                  color: palette.dangerForeground,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppRhythm.title),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: AppRhythm.tight,
            runSpacing: AppRhythm.tight,
            children: [
              TextButton(
                onPressed: sending ? null : () => Navigator.of(context).pop(),
                child: Text(copy.text('Cancel', 'Anuluj')),
              ),
              FilledButton.icon(
                key: const ValueKey('bug-report-send'),
                onPressed: sending ? null : _send,
                icon: sending
                    ? SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          semanticsLabel: copy.text(
                            'Sending report',
                            'Wysyłanie zgłoszenia',
                          ),
                        ),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(
                  _errorCode == null
                      ? copy.text('Send report', 'Wyślij zgłoszenie')
                      : copy.text('Try again', 'Spróbuj ponownie'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _screenshotSection(
    BuildContext context,
    AppLocalizations copy,
    bool sending,
  ) {
    final palette = context.appPalette;
    final text = Theme.of(context).textTheme;
    final bytes = widget.screenshot;

    Widget note(String message, IconData icon) => Row(
      children: [
        Icon(icon, size: 18, color: palette.textTertiary),
        const SizedBox(width: AppRhythm.tight),
        Expanded(
          child: Text(
            message,
            style: text.bodySmall?.copyWith(color: palette.textSecondary),
          ),
        ),
      ],
    );

    if (widget.captureBlocked) {
      return KeyedSubtree(
        key: const ValueKey('bug-report-screenshot-blocked'),
        child: note(
          copy.text(
            'Screenshots are off on this screen to protect sensitive information.',
            'Na tym ekranie zrzuty są wyłączone, aby chronić poufne informacje.',
          ),
          Icons.no_photography_outlined,
        ),
      );
    }
    if (bytes == null) {
      return note(
        copy.text(
          'No screenshot is available for this report.',
          'Dla tego zgłoszenia nie ma zrzutu ekranu.',
        ),
        Icons.hide_image_outlined,
      );
    }
    if (!_screenshotConfirmed) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: OutlinedButton.icon(
          key: const ValueKey('bug-report-screenshot-review'),
          onPressed: sending ? null : _reviewScreenshot,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: Text(
            copy.text(
              'Review and attach a screenshot',
              'Przejrzyj i dołącz zrzut ekranu',
            ),
          ),
        ),
      );
    }
    return Container(
      key: const ValueKey('bug-report-screenshot-attached'),
      padding: const EdgeInsets.all(AppRhythm.tight),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: AppRadius.sm,
            child: Image.memory(
              bytes,
              width: 56,
              height: 96,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              semanticLabel: copy.text(
                'Attached screenshot',
                'Dołączony zrzut ekranu',
              ),
            ),
          ),
          const SizedBox(width: AppRhythm.item),
          Expanded(
            child: Text(
              copy.text('Screenshot attached', 'Zrzut ekranu dołączony'),
              style: text.bodyMedium?.copyWith(color: palette.textPrimary),
            ),
          ),
          TextButton(
            key: const ValueKey('bug-report-screenshot-remove'),
            onPressed: sending
                ? null
                : () => setState(() => _screenshotConfirmed = false),
            child: Text(copy.text('Remove', 'Usuń')),
          ),
        ],
      ),
    );
  }

  Widget _sentView(BuildContext context, AppLocalizations copy) {
    final palette = context.appPalette;
    final text = Theme.of(context).textTheme;
    final result = _result!;
    final shortId = result.reportId.length > 11
        ? result.reportId.substring(0, 11)
        : result.reportId;
    return SingleChildScrollView(
      key: const ValueKey('bug-report-sent'),
      padding: const EdgeInsets.all(AppRhythm.section),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.check_circle_rounded,
            size: 44,
            color: palette.successForeground,
          ),
          const SizedBox(height: AppRhythm.item),
          Text(
            copy.text(
              'Thanks, your report was sent.',
              'Dziękujemy, zgłoszenie zostało wysłane.',
            ),
            textAlign: TextAlign.center,
            style: text.titleMedium?.copyWith(
              color: palette.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (result.screenshotRequested && !result.screenshotAttached) ...[
            const SizedBox(height: AppRhythm.tight),
            Text(
              copy.text(
                'The screenshot could not be attached, but your description arrived.',
                'Nie udało się dołączyć zrzutu ekranu, ale opis dotarł.',
              ),
              key: const ValueKey('bug-report-screenshot-failed'),
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: palette.textSecondary),
            ),
          ],
          const SizedBox(height: AppRhythm.tight),
          SelectableText(
            copy.template(
              'Reference: {id}',
              'Numer zgłoszenia: {id}',
              values: <String, Object>{'id': shortId},
            ),
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(color: palette.textTertiary),
          ),
          const SizedBox(height: AppRhythm.title),
          Center(
            child: FilledButton(
              key: const ValueKey('bug-report-done'),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(copy.text('Done', 'Gotowe')),
            ),
          ),
        ],
      ),
    );
  }
}

/// The consent step: the full captured frame, a plain note, and an explicit
/// choice. Returns true only for "Attach screenshot".
class _ScreenshotPreviewDialog extends StatelessWidget {
  const _ScreenshotPreviewDialog({required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final text = Theme.of(context).textTheme;
    final height = MediaQuery.sizeOf(context).height;
    return AlertDialog(
      key: const ValueKey('bug-report-screenshot-preview'),
      backgroundColor: palette.surfaceRaised,
      title: Text(
        copy.text('Attach this screenshot?', 'Dołączyć ten zrzut ekranu?'),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The note comes first, so it is read before the picture and is
            // never scrolled out of view by a tall screenshot.
            Container(
              key: const ValueKey('bug-report-screenshot-warning'),
              padding: const EdgeInsets.all(AppRhythm.item),
              decoration: BoxDecoration(
                color: palette.warningSurface,
                borderRadius: AppRadius.card,
              ),
              child: Text(
                copy.text(
                  'This screenshot may show other people\'s names, photos or messages. Attach it only if you are OK with the YO Voice team seeing everything visible here.',
                  'Ten zrzut może pokazywać imiona, zdjęcia lub wiadomości innych osób. Dołącz go tylko wtedy, gdy zgadzasz się, by zespół YO Voice zobaczył wszystko, co jest na nim widoczne.',
                ),
                style: text.bodyMedium?.copyWith(
                  color: palette.warningForeground,
                ),
              ),
            ),
            const SizedBox(height: AppRhythm.item),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: height * .4),
              child: ClipRRect(
                borderRadius: AppRadius.card,
                child: Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  semanticLabel: copy.text(
                    'Screenshot of the screen you were on',
                    'Zrzut ekranu, na którym byłeś',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('bug-report-screenshot-decline'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(copy.text('Don\'t attach', 'Nie dołączaj')),
        ),
        FilledButton(
          key: const ValueKey('bug-report-screenshot-confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(copy.text('Attach screenshot', 'Dołącz zrzut')),
        ),
      ],
    );
  }
}
