import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/settings/data/models/message_privacy.dart';
import 'package:yovoice/features/settings/data/services/message_privacy_service.dart';
import 'package:yovoice/features/settings/presentation/screens/message_privacy_screen.dart';

/// Drop-in Settings child. It owns only the row and route; the parent Settings
/// group still owns section borders/dividers.
class MessagePrivacySettingsTile extends StatefulWidget {
  const MessagePrivacySettingsTile({this.service, super.key});

  final MessagePrivacyService? service;

  @override
  State<MessagePrivacySettingsTile> createState() =>
      _MessagePrivacySettingsTileState();
}

class _MessagePrivacySettingsTileState
    extends State<MessagePrivacySettingsTile> {
  late final MessagePrivacyService _service =
      widget.service ?? MessagePrivacyService();

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return StreamBuilder<MessagePrivacyOption>(
      stream: _service.watchCurrent(),
      builder: (context, snapshot) {
        final subtitle = snapshot.hasError
            ? copy.text(
                'Could not load this preference',
                'Nie udało się wczytać tego ustawienia',
              )
            : snapshot.hasData
            ? _localizedOptionLabel(copy, snapshot.data!)
            : copy.text('Loading…', 'Wczytywanie…');
        return ListTile(
          key: const ValueKey('message-privacy-settings-tile'),
          onTap: snapshot.hasData
              ? () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MessagePrivacyScreen(service: _service),
                  ),
                )
              : null,
          leading: Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.forum_outlined,
              color: colors.onPrimaryContainer,
              size: 20,
            ),
          ),
          title: Text(
            copy.text('Who can message you', 'Kto może do Ciebie pisać'),
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 14.5,
            ),
          ),
          subtitle: Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: palette.textSecondary, fontSize: 12),
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: palette.textSecondary,
          ),
        );
      },
    );
  }
}

String _localizedOptionLabel(
  AppLocalizations copy,
  MessagePrivacyOption option,
) => switch (option) {
  MessagePrivacyOption.everyone => copy.text('Everyone', 'Wszyscy'),
  MessagePrivacyOption.peopleYouFollow => copy.text(
    'People you follow',
    'Obserwowane osoby',
  ),
  MessagePrivacyOption.friends => copy.text('Friends only', 'Tylko znajomi'),
  MessagePrivacyOption.nobody => copy.text('Nobody', 'Nikt'),
};
