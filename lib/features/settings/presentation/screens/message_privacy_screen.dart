import 'package:flutter/material.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/settings/data/models/message_privacy.dart';
import 'package:yovoice/features/settings/data/services/message_privacy_service.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';
import 'package:yovoice/shared/widgets/states/yo_loading_indicator.dart';

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
            content: Text(
              AppLocalizations.of(context).text(
                'Direct messages: ${next.label}.',
                'Wiadomości bezpośrednie: ${_optionLabel(context, next)}.',
              ),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).text(
                friendlyErrorMessage(error),
                'Nie udało się zapisać ustawień wiadomości. Spróbuj ponownie.',
              ),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
          ),
        );
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        foregroundColor: palette.textPrimary,
        title: Text(
          copy.text('Who can message you', 'Kto może do Ciebie pisać'),
        ),
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
                return YoErrorState(
                  message: copy.text(
                    friendlyErrorMessage(snapshot.error!),
                    'Nie udało się wczytać ustawień wiadomości.',
                  ),
                  compact: true,
                );
              }
              final selected = snapshot.data;
              if (selected == null) {
                return YoLoadingIndicator.fullscreen(
                  message: copy.text(
                    'Loading message privacy…',
                    'Ładowanie ustawień wiadomości…',
                  ),
                );
              }
              return LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 640;
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(0, 18, 0, 36),
                    children: [
                      Text(
                        copy.text(
                          'Choose your inbox boundary',
                          'Wybierz, kto może do Ciebie pisać',
                        ),
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        copy.text(
                          'This applies immediately to conversation starts and every new text, photo and voice message. It never deletes your history.',
                          'Zmiana działa od razu dla nowych rozmów oraz każdej nowej wiadomości tekstowej, zdjęcia i wiadomości głosowej. Historia rozmów pozostaje bez zmian.',
                        ),
                        style: TextStyle(
                          color: palette.textSecondary,
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
                          color: palette.surface,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: palette.border),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.shield_outlined,
                              color: colors.primary,
                              size: 21,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                copy.text(
                                  'Blocking someone always overrides this setting. Relationship checks happen on YO Voice servers, so altered apps cannot bypass your choice.',
                                  'Zablokowanie osoby zawsze ma pierwszeństwo przed tym ustawieniem. Uprawnienia są sprawdzane na serwerach YO Voice, więc zmodyfikowana aplikacja nie może ominąć Twojego wyboru.',
                                ),
                                style: TextStyle(
                                  color: palette.textSecondary,
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
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final label = _optionLabel(context, option);
    final description = _optionDescription(context, option);
    return Semantics(
      button: true,
      selected: selected,
      enabled: !disabled,
      label: '$label. $description',
      value: saving ? copy.text('Saving', 'Zapisywanie') : null,
      liveRegion: saving,
      onTap: disabled ? null : onTap,
      excludeSemantics: true,
      child: Material(
        color: selected ? colors.primaryContainer : palette.surface,
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
                color: selected ? colors.primary : palette.border,
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
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(_icon, color: colors.primary, size: 21),
                    ),
                    const Spacer(),
                    if (saving)
                      SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.primary,
                        ),
                      )
                    else
                      Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: selected ? colors.primary : palette.textTertiary,
                      ),
                  ],
                ),
                const SizedBox(height: 13),
                Text(
                  label,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  description,
                  style: TextStyle(
                    color: palette.textSecondary,
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

String _optionLabel(BuildContext context, MessagePrivacyOption option) {
  final copy = AppLocalizations.of(context);
  return switch (option) {
    MessagePrivacyOption.everyone => copy.text('Everyone', 'Wszyscy'),
    MessagePrivacyOption.peopleYouFollow => copy.text(
      'People you follow',
      'Obserwowane osoby',
    ),
    MessagePrivacyOption.friends => copy.text('Friends only', 'Tylko znajomi'),
    MessagePrivacyOption.nobody => copy.text('Nobody', 'Nikt'),
  };
}

String _optionDescription(BuildContext context, MessagePrivacyOption option) {
  final copy = AppLocalizations.of(context);
  return switch (option) {
    MessagePrivacyOption.everyone => copy.text(
      'Any active YO Voice member can start a conversation with you.',
      'Każdy aktywny użytkownik YO Voice może rozpocząć z Tobą rozmowę.',
    ),
    MessagePrivacyOption.peopleYouFollow => copy.text(
      'Only people you chose to follow can send you a direct message.',
      'Wiadomość bezpośrednią mogą wysłać tylko osoby, które obserwujesz.',
    ),
    MessagePrivacyOption.friends => copy.text(
      'Only accepted friends can send new text, photo or voice messages.',
      'Nowe wiadomości tekstowe, zdjęcia i wiadomości głosowe mogą wysyłać tylko zaakceptowani znajomi.',
    ),
    MessagePrivacyOption.nobody => copy.text(
      'No one can send you new direct messages. Your existing history stays visible.',
      'Nikt nie może wysyłać Ci nowych wiadomości bezpośrednich. Dotychczasowa historia pozostaje widoczna.',
    ),
  };
}
