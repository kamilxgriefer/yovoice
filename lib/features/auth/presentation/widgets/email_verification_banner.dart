import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';

/// Persistent, account-level reminder shown above authenticated content.
///
/// Verification is intentionally never represented as a dismissible notice:
/// closing it would hide an account requirement without changing the account.
/// The whole surface is one generous tap target that opens the verification
/// flow, while the text remains concise enough for compact phones and Polish.
class EmailVerificationBanner extends StatelessWidget {
  const EmailVerificationBanner({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final action = copy.text('Verify now', 'Zweryfikuj teraz');
    return Material(
      color: palette.warningSurface,
      child: Semantics(
        button: true,
        excludeSemantics: true,
        onTap: onTap,
        label: copy.text(
          'Your email is not verified. Verify now.',
          'Twój adres e-mail nie jest zweryfikowany. Zweryfikuj teraz.',
        ),
        child: InkWell(
          key: const ValueKey('email-verification-banner'),
          onTap: onTap,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact =
                      constraints.maxWidth < 360 ||
                      MediaQuery.textScalerOf(context).scale(1) >= 1.5;
                  final message = Text(
                    copy.text(
                      "Your email isn't verified yet.",
                      'Twój adres e-mail nie został jeszcze zweryfikowany.',
                    ),
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                  final actionLabel = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          action,
                          style: TextStyle(
                            color: palette.warningForeground,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: palette.warningForeground,
                        size: 18,
                      ),
                    ],
                  );

                  return Row(
                    crossAxisAlignment: compact
                        ? CrossAxisAlignment.start
                        : CrossAxisAlignment.center,
                    children: [
                      Padding(
                        padding: EdgeInsets.only(top: compact ? 2 : 0),
                        child: Icon(
                          Icons.mark_email_unread_outlined,
                          color: palette.warningForeground,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: compact
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  message,
                                  const SizedBox(height: 4),
                                  actionLabel,
                                ],
                              )
                            : Row(
                                children: [
                                  Expanded(child: message),
                                  const SizedBox(width: 8),
                                  actionLabel,
                                ],
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
