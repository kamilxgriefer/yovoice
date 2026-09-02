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
  final _searchController = TextEditingController();
  AppLanguagePreference? _saving;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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
    final query = _query.trim().toLowerCase();
    final languages = selectableAppLanguages
        .where((language) {
          if (query.isEmpty) return true;
          return language.nativeName.toLowerCase().contains(query) ||
              language.englishName.toLowerCase().contains(query) ||
              copy.languageName(language).toLowerCase().contains(query) ||
              language.localeKey.toLowerCase().contains(query);
        })
        .toList(growable: false);

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
                copy.chooseLanguage,
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              _LanguageChoice(
                title: copy.systemLanguage,
                subtitle: copy.systemLanguageDescription,
                code: AppLanguagePreference.system.badge,
                selected: selected == AppLanguagePreference.system,
                saving: _saving == AppLanguagePreference.system,
                disabled: _saving != null,
                onTap: () => _select(AppLanguagePreference.system),
              ),
              const SizedBox(height: 20),
              TextField(
                key: const ValueKey('language-search'),
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: copy.searchLanguages,
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: MaterialLocalizations.of(
                            context,
                          ).deleteButtonTooltip,
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
              ),
              const SizedBox(height: 14),
              if (languages.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Column(
                    children: [
                      Icon(
                        Icons.translate_rounded,
                        size: 36,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        copy.noLanguagesFound,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              else
                for (final language in languages) ...[
                  _LanguageChoice(
                    key: ValueKey('language-${language.localeKey}'),
                    title: language.nativeName,
                    subtitle: copy.languageName(language),
                    code: language.badge,
                    selected: selected == language,
                    saving: _saving == language,
                    disabled: _saving != null,
                    onTap: () => _select(language),
                  ),
                  if (language != languages.last) const SizedBox(height: 12),
                ],
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

class _LanguageChoice extends StatefulWidget {
  const _LanguageChoice({
    required this.title,
    required this.subtitle,
    required this.code,
    required this.selected,
    required this.saving,
    required this.disabled,
    required this.onTap,
    super.key,
  });

  final String title;
  final String subtitle;
  final String code;
  final bool selected;
  final bool saving;
  final bool disabled;
  final VoidCallback onTap;

  @override
  State<_LanguageChoice> createState() => _LanguageChoiceState();
}

class _LanguageChoiceState extends State<_LanguageChoice> {
  late final FocusNode _focusNode = FocusNode(
    debugLabel: 'language-choice-${widget.code}',
  );
  bool _focused = false;

  @override
  void didUpdateWidget(_LanguageChoice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.disabled && _focusNode.hasFocus) _focusNode.unfocus();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);
    return Semantics(
      selected: widget.selected,
      button: true,
      enabled: !widget.disabled,
      label: '${widget.title}. ${widget.subtitle}',
      value: widget.saving ? copy.text('Saving', 'Zapisywanie') : null,
      liveRegion: widget.saving,
      onTap: widget.disabled ? null : widget.onTap,
      excludeSemantics: true,
      child: Material(
        color: widget.selected
            ? colors.primary.withValues(alpha: .1)
            : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: _focused || widget.selected
                ? colors.primary
                : colors.outlineVariant,
            width: _focused
                ? 3
                : widget.selected
                ? 2
                : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          focusNode: _focusNode,
          canRequestFocus: !widget.disabled,
          focusColor: colors.primary.withValues(alpha: .12),
          onFocusChange: (focused) {
            if (_focused != focused) setState(() => _focused = focused);
          },
          onTap: widget.disabled ? null : widget.onTap,
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
                      widget.code,
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
                          widget.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          widget.subtitle,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (widget.saving)
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
                      widget.selected
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      color: widget.selected ? colors.primary : colors.outline,
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
