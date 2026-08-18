import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/preferences/app_preferences.dart';
import 'package:yovoice/features/settings/presentation/screens/app_language_screen.dart';
import 'package:yovoice/features/settings/presentation/screens/appearance_settings_screen.dart';

/// Drop-in Settings content for the two former Coming Soon groups.
///
/// Kept outside settings_screen.dart so preference ownership and tests do not
/// depend on that large, frequently edited integration surface.
class AppearanceLanguageSettingsSection extends StatelessWidget {
  const AppearanceLanguageSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final preferences = AppPreferencesScope.of(context).value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel(copy.appearance),
        _PreferenceGroup(
          child: _PreferenceTile(
            icon: _themeIcon(preferences.theme),
            title: copy.theme,
            subtitle: _themeLabel(copy, preferences.theme),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AppearanceSettingsScreen(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 22),
        _SectionLabel(copy.language),
        _PreferenceGroup(
          child: _PreferenceTile(
            icon: Icons.translate_rounded,
            title: copy.appLanguage,
            subtitle: _languageLabel(copy, preferences.language),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AppLanguageScreen(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 22),
      ],
    );
  }

  static IconData _themeIcon(AppThemePreference theme) => switch (theme) {
    AppThemePreference.system => Icons.brightness_auto_rounded,
    AppThemePreference.dark => Icons.dark_mode_rounded,
    AppThemePreference.light => Icons.light_mode_rounded,
  };

  static String _themeLabel(AppLocalizations copy, AppThemePreference theme) =>
      switch (theme) {
        AppThemePreference.system => copy.systemTheme,
        AppThemePreference.dark => copy.darkTheme,
        AppThemePreference.light => '${copy.lightTheme} · Beta',
      };

  static String _languageLabel(
    AppLocalizations copy,
    AppLanguagePreference language,
  ) => switch (language) {
    AppLanguagePreference.system => copy.systemLanguage,
    AppLanguagePreference.english => 'English',
    AppLanguagePreference.polish => 'Polski · Beta',
  };
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _PreferenceGroup extends StatelessWidget {
  const _PreferenceGroup({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _PreferenceTile extends StatelessWidget {
  const _PreferenceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      minTileHeight: 72,
      onTap: onTap,
      leading: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.primary.withValues(alpha: .13),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(icon, color: colors.primary, size: 22),
      ),
      title: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        subtitle,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: colors.onSurfaceVariant,
      ),
    );
  }
}
