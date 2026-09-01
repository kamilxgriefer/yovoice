import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/preferences/app_preferences.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';

class AppLanguageScreen extends StatefulWidget {
  const AppLanguageScreen({super.key});

  @override
  State<AppLanguageScreen> createState() => _AppLanguageScreenState();
}

class _AppLanguageScreenState extends State<AppLanguageScreen> {
  AppLanguagePreference? _saving;

  Future<void> _select(AppLanguagePreference preference) async {
    if (_saving != null) return;
    setState(() => _saving = preference);
    try {
      await AppPreferencesScope.of(context).setLanguage(preference);
    } catch (_) {
      if (mounted) {
        final copy = AppLocalizations.of(context);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(copy.saveFailed)));
      }
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final selected = AppPreferencesScope.of(context).value.language;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(copy.appLanguage)),
      body: SafeArea(
        top: false,
        child: ResponsiveContentFrame(
          width: ResponsiveContentWidth.form,
          alignment: ResponsiveContentAlignment.topLeft,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            children: [
              Text(
                copy.text(
                  'Choose the language used on this device.',
                  'Wybierz język używany na tym urządzeniu.',
                ),
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              _LanguageChoice(
                title: copy.systemLanguage,
                subtitle: copy.text(
                  'Uses Polish when your device is set to Polish, otherwise English.',
                  'Używa polskiego, gdy urządzenie jest ustawione na polski; w przeciwnym razie angielskiego.',
                ),
                code: 'A',
                selected: selected == AppLanguagePreference.system,
                saving: _saving == AppLanguagePreference.system,
                disabled: _saving != null,
                onTap: () => _select(AppLanguagePreference.system),
              ),
              const SizedBox(height: 12),
              _LanguageChoice(
                title: 'English',
                subtitle: 'English',
                code: 'EN',
                selected: selected == AppLanguagePreference.english,
                saving: _saving == AppLanguagePreference.english,
                disabled: _saving != null,
                onTap: () => _select(AppLanguagePreference.english),
              ),
              const SizedBox(height: 12),
              _LanguageChoice(
                title: 'Polski · Beta',
                subtitle: 'Polish',
                code: 'PL',
                selected: selected == AppLanguagePreference.polish,
                saving: _saving == AppLanguagePreference.polish,
                disabled: _saving != null,
                onTap: () => _select(AppLanguagePreference.polish),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: colors.primary.withValues(alpha: .28),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.translate_rounded, color: colors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            copy.languagePreviewTitle,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            copy.languagePreviewBody,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: colors.onSurfaceVariant),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            copy.savedOnDevice,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageChoice extends StatelessWidget {
  const _LanguageChoice({
    required this.title,
    required this.subtitle,
    required this.code,
    required this.selected,
    required this.saving,
    required this.disabled,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String code;
  final bool selected;
  final bool saving;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);
    return Semantics(
      selected: selected,
      button: true,
      enabled: !disabled,
      label: '$title. $subtitle',
      value: saving ? copy.text('Saving', 'Zapisywanie') : null,
      liveRegion: saving,
      onTap: disabled ? null : onTap,
      excludeSemantics: true,
      child: Material(
        color: selected ? colors.primary.withValues(alpha: .1) : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: selected ? colors.primary : colors.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: disabled ? null : onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 80),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Text(
                      code,
                      style: Theme.of(
                        context,
                      ).textTheme.labelLarge?.copyWith(color: colors.primary),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (saving)
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: colors.primary,
                      ),
                    )
                  else
                    Icon(
                      selected
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      color: selected ? colors.primary : colors.outline,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
