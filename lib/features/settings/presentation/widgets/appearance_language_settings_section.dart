import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/preferences/app_preferences.dart';
import 'package:yovoice/core/theme/app_palette.dart';
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
        const SizedBox(height: 24),
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
        const SizedBox(height: 24),
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
        AppThemePreference.light => copy.lightTheme,
      };

  static String _languageLabel(
    AppLocalizations copy,
    AppLanguagePreference language,
  ) => switch (language) {
    AppLanguagePreference.system => copy.systemLanguage,
    _ => language.nativeName,
  };
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  // Matches Settings' own group labels (Slim: 11 px w700 uppercase, .08em)
  // so the two drop-in groups do not read as a different screen.
  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            color: context.appPalette.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 11 * .08,
          ),
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
    final palette = context.appPalette;
    // The same flat group as the Settings rows around it: one layer, 1 px
    // `palette.border`, radius 12.
    return Material(
      color: palette.surfaceMuted,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: palette.border),
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
    final palette = context.appPalette;
    // Slim row, identical geometry to `_SettingsTile`: 64 px floor, 40 px
    // tonal leading box, 22 px glyph.
    return ListTile(
      minTileHeight: 64,
      contentPadding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
      minLeadingWidth: 40,
      horizontalTitleGap: 12,
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: colors.onPrimaryContainer, size: 22),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: palette.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: palette.textSecondary, fontSize: 12.5),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: palette.textTertiary),
    );
  }
}
