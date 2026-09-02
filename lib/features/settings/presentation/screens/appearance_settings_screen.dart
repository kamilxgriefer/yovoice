import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/preferences/app_preferences.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';

class AppearanceSettingsScreen extends StatefulWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  State<AppearanceSettingsScreen> createState() =>
      _AppearanceSettingsScreenState();
}

class _AppearanceSettingsScreenState extends State<AppearanceSettingsScreen> {
  AppThemePreference? _saving;

  Future<void> _select(AppThemePreference preference) async {
    if (_saving != null) return;
    setState(() => _saving = preference);
    try {
      await AppPreferencesScope.of(context).setTheme(preference);
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
    final selected = AppPreferencesScope.of(context).value.theme;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(copy.appearance)),
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
                  'Choose how YO Voice looks on this device.',
                  'Wybierz wygląd YO Voice na tym urządzeniu.',
                ),
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              _PreferenceChoice(
                icon: Icons.brightness_auto_rounded,
                title: copy.systemTheme,
                subtitle: copy.text(
                  'Follows your device light or dark appearance.',
                  'Dopasowuje się do jasnego lub ciemnego motywu urządzenia.',
                ),
                selected: selected == AppThemePreference.system,
                saving: _saving == AppThemePreference.system,
                disabled: _saving != null,
                onTap: () => _select(AppThemePreference.system),
              ),
              const SizedBox(height: 12),
              _PreferenceChoice(
                icon: Icons.dark_mode_rounded,
                title: copy.darkTheme,
                subtitle: copy.text(
                  'The original cosmic YO Voice appearance.',
                  'Oryginalny, kosmiczny wygląd YO Voice.',
                ),
                selected: selected == AppThemePreference.dark,
                saving: _saving == AppThemePreference.dark,
                disabled: _saving != null,
                onTap: () => _select(AppThemePreference.dark),
              ),
              const SizedBox(height: 12),
              _PreferenceChoice(
                icon: Icons.light_mode_rounded,
                title: copy.lightTheme,
                subtitle: copy.text(
                  'Pearl surfaces, ink contrast and the signature YO glow for daytime.',
                  'Jasne perłowe powierzchnie, wysoki kontrast i charakterystyczny blask YO.',
                ),
                selected: selected == AppThemePreference.light,
                saving: _saving == AppThemePreference.light,
                disabled: _saving != null,
                onTap: () => _select(AppThemePreference.light),
              ),
              const SizedBox(height: 20),
              _InfoCard(icon: Icons.devices_rounded, text: copy.savedOnDevice),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreferenceChoice extends StatelessWidget {
  const _PreferenceChoice({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.saving,
    required this.disabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
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
        color: selected
            ? colors.primaryContainer.withValues(alpha: .72)
            : colors.surfaceContainerLow,
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
            constraints: const BoxConstraints(minHeight: 88),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(icon, color: colors.primary),
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
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodyMedium
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

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, color: colors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
