import 'package:flutter/material.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/profile/data/models/profile_visibility.dart';
import 'package:yovoice/features/profile/data/services/profile_visibility_service.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';

class ProfileVisibilityScreen extends StatefulWidget {
  const ProfileVisibilityScreen({
    required this.initialVisibility,
    this.service,
    this.isRootTab = false,
    super.key,
  });

  final ProfileVisibility initialVisibility;
  final ProfileVisibilityService? service;
  final bool isRootTab;

  @override
  State<ProfileVisibilityScreen> createState() =>
      _ProfileVisibilityScreenState();
}

class _ProfileVisibilityScreenState extends State<ProfileVisibilityScreen> {
  late final ProfileVisibilityService _service =
      widget.service ?? ProfileVisibilityService();
  late ProfileVisibility _visibility = widget.initialVisibility;
  ProfileVisibility? _saving;

  Future<void> _select(ProfileVisibility visibility) async {
    if (_saving != null || visibility == _visibility) return;
    setState(() => _saving = visibility);
    try {
      final saved = await _service.setVisibility(visibility);
      if (!mounted) return;
      setState(() => _visibility = saved);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).text(
                'Profile visibility set to ${saved.label}.',
                'Widoczność profilu: ${_visibilityLabel(context, saved)}.',
              ),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } on ProfileVisibilityException catch (error) {
      if (!mounted) return;
      final copy = AppLocalizations.of(context);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              friendlyErrorMessage(
                error,
                copy: copy,
                fallback: copy.text(
                  'Profile visibility could not be updated. Please try again.',
                  'Nie udało się zmienić widoczności profilu. Spróbuj ponownie.',
                ),
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
    return Scaffold(
      backgroundColor: palette.background,
      appBar: widget.isRootTab
          ? null
          : AppBar(
              backgroundColor: palette.background,
              foregroundColor: palette.textPrimary,
              title: Text(
                copy.text('Profile visibility', 'Widoczność profilu'),
              ),
            ),
      body: SafeArea(
        top: widget.isRootTab,
        child: ResponsiveContentFrame(
          width: ResponsiveContentWidth.list,
          alignment: ResponsiveContentAlignment.topCenter,
          child: ListView(
            key: const ValueKey('profile-visibility-content'),
            padding: EdgeInsets.fromLTRB(
              MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
              18,
              MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
              40,
            ),
            children: [
              if (widget.isRootTab) ...[
                Text(
                  copy.text('Profile visibility', 'Widoczność profilu'),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.5,
                  ),
                ),
                const SizedBox(height: 18),
              ],
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: palette.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _PrivacyIcon(),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            copy.text(
                              'Choose who sees your full profile',
                              'Wybierz, kto może zobaczyć pełny profil',
                            ),
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            copy.text(
                              'Your name can still appear where you participate, such as rooms, clubs and existing conversations. This setting controls your profile page and discovery.',
                              'Twoja nazwa nadal może być widoczna w miejscach, w których uczestniczysz — na przykład w pokojach, Klubach i istniejących rozmowach. To ustawienie określa widoczność strony profilu i możliwość znalezienia Cię.',
                            ),
                            style: TextStyle(
                              color: palette.textSecondary,
                              height: 1.45,
                              fontSize: 13.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              for (final visibility in ProfileVisibility.values) ...[
                _VisibilityOption(
                  visibility: visibility,
                  selected: visibility == _visibility,
                  busy: visibility == _saving,
                  enabled: _saving == null,
                  onTap: () => _select(visibility),
                ),
                if (visibility != ProfileVisibility.values.last)
                  const SizedBox(height: 10),
              ],
              const SizedBox(height: 18),
              Text(
                copy.text(
                  'Changes take effect immediately in YO Voice. Choosing Friends only or Only me also removes your profile from public website showcases.',
                  'Zmiany zaczynają działać natychmiast. Wybranie opcji „Tylko znajomi” lub „Tylko ja” usuwa też profil z publicznych prezentacji na stronie YO Voice.',
                ),
                style: TextStyle(
                  color: palette.textTertiary,
                  height: 1.45,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrivacyIcon extends StatelessWidget {
  const _PrivacyIcon();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Icon(Icons.visibility_outlined, color: colors.primary),
    );
  }
}

class _VisibilityOption extends StatelessWidget {
  const _VisibilityOption({
    required this.visibility,
    required this.selected,
    required this.busy,
    required this.enabled,
    required this.onTap,
  });

  final ProfileVisibility visibility;
  final bool selected;
  final bool busy;
  final bool enabled;
  final VoidCallback onTap;

  IconData get _icon => switch (visibility) {
    ProfileVisibility.public => Icons.public_rounded,
    ProfileVisibility.friends => Icons.people_alt_outlined,
    ProfileVisibility.private => Icons.lock_outline_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final label = _visibilityLabel(context, visibility);
    final description = _visibilityDescription(context, visibility);
    return Semantics(
      button: true,
      selected: selected,
      label: '$label. $description',
      child: Material(
        color: selected ? palette.surfaceMuted : palette.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          key: ValueKey('profile-visibility-${visibility.name}'),
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            constraints: const BoxConstraints(minHeight: 82),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? colors.primary : palette.border,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  _icon,
                  color: selected ? colors.primary : palette.textSecondary,
                  size: 24,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: TextStyle(
                          color: palette.textSecondary,
                          height: 1.35,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (busy)
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
          ),
        ),
      ),
    );
  }
}

String _visibilityLabel(BuildContext context, ProfileVisibility visibility) {
  final copy = AppLocalizations.of(context);
  return switch (visibility) {
    ProfileVisibility.public => copy.text('Everyone', 'Wszyscy'),
    ProfileVisibility.friends => copy.text('Friends only', 'Tylko znajomi'),
    ProfileVisibility.private => copy.text('Only me', 'Tylko ja'),
  };
}

String _visibilityDescription(
  BuildContext context,
  ProfileVisibility visibility,
) {
  final copy = AppLocalizations.of(context);
  return switch (visibility) {
    ProfileVisibility.public => copy.text(
      'Signed-in people can open your profile and find you in search.',
      'Zalogowane osoby mogą otworzyć Twój profil i znaleźć Cię w wyszukiwarce.',
    ),
    ProfileVisibility.friends => copy.text(
      'Only confirmed friends can open your full profile.',
      'Pełny profil mogą otworzyć tylko zaakceptowani znajomi.',
    ),
    ProfileVisibility.private => copy.text(
      'Your full profile is hidden from every other account.',
      'Pełny profil jest ukryty przed wszystkimi innymi osobami.',
    ),
  };
}
