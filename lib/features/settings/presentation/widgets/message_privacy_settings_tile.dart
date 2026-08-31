import 'package:flutter/material.dart';

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
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return StreamBuilder<MessagePrivacyOption>(
      stream: _service.watchCurrent(),
      builder: (context, snapshot) {
        final subtitle = snapshot.hasError
            ? 'Could not load this preference'
            : snapshot.hasData
            ? snapshot.data!.label
            : 'Loading…';
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
            'Who can message you',
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
