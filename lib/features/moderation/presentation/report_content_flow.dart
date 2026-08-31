import 'package:flutter/material.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/moderation/data/services/content_report_service.dart';
import 'package:yovoice/features/moderation/presentation/widgets/report_reason_sheet.dart';

/// The one report-a-piece-of-content flow, shared by every surface that
/// offers one.
///
/// It exists so the surfaces cannot drift. A report action wired
/// separately into direct messages, the Moments feed and Moment comments
/// would, within two changes, be three subtly different flows with three
/// different failure sentences — and a reporter who is told "something
/// went wrong" on one screen and "you already reported this" on another
/// for the same underlying state has been told nothing. Reason picker,
/// success copy, failure copy and the snackbar treatment all live here.
///
/// Returns true only when a report was actually filed. Backing out of the
/// picker returns false and is not an error.
Future<bool> reportContent({
  required BuildContext context,
  required ReportedContent content,
  required String title,
  required String subtitle,
  ContentReportService? service,
}) async {
  // Captured before the first await: the calling widget (a message
  // bubble, a Moment card) can be disposed while the sheet is open, and
  // its context would then be dead by the time there is something to
  // say. The messenger outlives it.
  final messenger = ScaffoldMessenger.maybeOf(context);
  final palette = context.appPalette;

  final reason = await showReportReasonSheet(
    context: context,
    title: title,
    subtitle: subtitle,
  );
  if (reason == null) return false;

  try {
    await (service ?? ContentReportService()).report(
      content: content,
      reason: reason,
    );
    _say(messenger, palette, 'Thanks — your report is with our team.');
    return true;
  } catch (error) {
    // ContentReportException is a StateError carrying deliberate copy,
    // so this surfaces the specific reason; anything unexpected is
    // laundered instead of being pasted into the UI raw.
    _say(
      messenger,
      palette,
      intentionalOrFriendly(
        error,
        fallback: 'Your report could not be sent. Please try again.',
      ),
      isError: true,
    );
    return false;
  }
}

/// The outcome, said once, legibly.
///
/// Three things here are deliberate, and all three came out of looking at
/// the rendered result rather than at the code:
///
///  * an explicit semantic status pair, because inverse-surface snackbar
///    defaults do not communicate success versus failure consistently in
///    both Dark and Pearl, and the one sentence explaining a failed safety
///    action is the last sentence in the app that should be hard to read;
///  * an icon, so success and failure are not distinguished by wording
///    alone for someone skimming, or by colour alone for someone who
///    cannot separate the two;
///  * six seconds on a failure against four on a success, because
///    "you already reported this" is something to read and act on, and
///    "thanks" is not.
void _say(
  ScaffoldMessengerState? messenger,
  AppPalette palette,
  String message, {
  bool isError = false,
}) {
  final statusSurface = isError
      ? palette.dangerSurface
      : palette.successSurface;
  final statusForeground = isError
      ? palette.dangerForeground
      : palette.successForeground;

  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        key: const ValueKey('report-result-snackbar'),
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              size: 20,
              color: statusForeground,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: statusForeground,
                  fontSize: 14,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: statusSurface,
        margin: const EdgeInsets.all(16),
        duration: Duration(seconds: isError ? 6 : 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: statusForeground),
        ),
      ),
    );
}
