import 'package:flutter/material.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/features/settings/data/models/message_privacy.dart';
import 'package:yovoice/features/settings/data/services/message_privacy_service.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';

class MessagePrivacyScreen extends StatefulWidget {
  const MessagePrivacyScreen({this.service, super.key});

  final MessagePrivacyService? service;

  @override
  State<MessagePrivacyScreen> createState() => _MessagePrivacyScreenState();
}

class _MessagePrivacyScreenState extends State<MessagePrivacyScreen> {
  late final MessagePrivacyService _service =
      widget.service ?? MessagePrivacyService();
  MessagePrivacyOption? _saving;

  Future<void> _select(
    MessagePrivacyOption current,
    MessagePrivacyOption next,
  ) async {
    if (_saving != null || current == next) return;
    setState(() => _saving = next);
    try {
      await _service.setCurrent(next);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Direct messages: ${next.label}.'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.surfaceLight,
          ),
        );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(friendlyErrorMessage(error)),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.error,
          ),
        );
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        title: const Text('Who can message you'),
      ),
      body: SafeArea(
        top: false,
        child: ResponsiveContentFrame(
          width: ResponsiveContentWidth.form,
          padding: ResponsiveContentFrame.adaptivePagePadding(
            MediaQuery.sizeOf(context).width,
          ),
          child: StreamBuilder<MessagePrivacyOption>(
            stream: _service.watchCurrent(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _MessagePrivacyError(
                  message: friendlyErrorMessage(snapshot.error!),
                );
              }
              final selected = snapshot.data;
              if (selected == null) {
                return const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                );
              }
              return LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 640;
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(0, 18, 0, 36),
                    children: [
                      const Text(
                        'Choose your inbox boundary',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'This applies immediately to conversation starts and every new text, photo and voice message. It never deletes your history.',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          height: 1.45,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 22),
                      if (wide)
                        Wrap(
                          spacing: 14,
                          runSpacing: 14,
                          children: [
                            for (final option in MessagePrivacyOption.values)
                              SizedBox(
                                width: (constraints.maxWidth - 14) / 2,
                                child: _PrivacyOptionCard(
                                  option: option,
                                  selected: selected == option,
                                  saving: _saving == option,
                                  disabled: _saving != null,
                                  onTap: () => _select(selected, option),
                                ),
                              ),
                          ],
                        )
                      else
                        Column(
                          children: [
                            for (
                              var index = 0;
                              index < MessagePrivacyOption.values.length;
                              index++
                            ) ...[
                              if (index > 0) const SizedBox(height: 12),
                              _PrivacyOptionCard(
                                option: MessagePrivacyOption.values[index],
                                selected:
                                    selected ==
                                    MessagePrivacyOption.values[index],
                                saving:
                                    _saving ==
                                    MessagePrivacyOption.values[index],
                                disabled: _saving != null,
                                onTap: () => _select(
                                  selected,
                                  MessagePrivacyOption.values[index],
                                ),
                              ),
                            ],
                          ],
                        ),
                      const SizedBox(height: 22),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.shield_outlined,
                              color: AppColors.accent,
                              size: 21,
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Blocking someone always overrides this setting. Relationship checks happen on YO Voice servers, so altered apps cannot bypass your choice.',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  height: 1.4,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PrivacyOptionCard extends StatelessWidget {
  const _PrivacyOptionCard({
    required this.option,
    required this.selected,
    required this.saving,
    required this.disabled,
    required this.onTap,
  });

  final MessagePrivacyOption option;
  final bool selected;
  final bool saving;
  final bool disabled;
  final VoidCallback onTap;

  IconData get _icon => switch (option) {
    MessagePrivacyOption.everyone => Icons.public_rounded,
    MessagePrivacyOption.peopleYouFollow => Icons.person_add_alt_1_rounded,
    MessagePrivacyOption.friends => Icons.people_alt_rounded,
    MessagePrivacyOption.nobody => Icons.do_not_disturb_alt_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${option.label}. ${option.description}',
      child: Material(
        color: selected
            ? AppColors.primary.withValues(alpha: .18)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          key: ValueKey('message-privacy-${option.storageValue}'),
          onTap: disabled ? null : onTap,
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(16),
            constraints: const BoxConstraints(minHeight: 142),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? AppColors.secondary : AppColors.border,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: .18),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(_icon, color: AppColors.secondary, size: 21),
                    ),
                    const Spacer(),
                    if (saving)
                      const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.secondary,
                        ),
                      )
                    else
                      Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: selected
                            ? AppColors.secondary
                            : AppColors.textHint,
                      ),
                  ],
                ),
                const SizedBox(height: 13),
                Text(
                  option.label,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  option.description,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    height: 1.35,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MessagePrivacyError extends StatelessWidget {
  const _MessagePrivacyError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.error),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
