import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
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
            content: Text('Profile visibility set to ${saved.label}.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } on ProfileVisibilityException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(error.message),
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
      appBar: widget.isRootTab
          ? null
          : AppBar(
              backgroundColor: AppColors.background,
              foregroundColor: AppColors.textPrimary,
              title: const Text('Profile visibility'),
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
                const Text(
                  'Profile visibility',
                  style: TextStyle(
                    color: AppColors.textPrimary,
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
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PrivacyIcon(),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Choose who sees your full profile',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Your name can still appear where you participate, such as rooms, clubs and existing conversations. This setting controls your profile page and discovery.',
                            style: TextStyle(
                              color: AppColors.textSecondary,
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
              const Text(
                'Changes take effect immediately in YO Voice. Choosing Friends only or Only me also removes your profile from public website showcases.',
                style: TextStyle(
                  color: AppColors.textHint,
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
    return Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(15),
      ),
      child: const Icon(Icons.visibility_outlined, color: AppColors.secondary),
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
    return Semantics(
      button: true,
      selected: selected,
      label: '${visibility.label}. ${visibility.description}',
      child: Material(
        color: selected ? AppColors.surfaceLight : AppColors.surface,
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
                color: selected ? AppColors.secondary : AppColors.border,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  _icon,
                  color: selected
                      ? AppColors.secondary
                      : AppColors.textSecondary,
                  size: 24,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        visibility.label,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        visibility.description,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          height: 1.35,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (busy)
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
                    color: selected ? AppColors.success : AppColors.textHint,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
