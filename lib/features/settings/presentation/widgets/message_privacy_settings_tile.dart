import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
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
              color: AppColors.primary.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.forum_outlined,
              color: AppColors.secondary,
              size: 20,
            ),
          ),
          title: const Text(
            'Who can message you',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 14.5,
            ),
          ),
          subtitle: Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          trailing: const Icon(
            Icons.chevron_right_rounded,
            color: AppColors.textSecondary,
          ),
        );
      },
    );
  }
}
