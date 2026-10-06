import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/pages/data/models/page_views.dart';
import 'package:yovoice/features/pages/data/services/page_access_service.dart';
import 'package:yovoice/features/pages/data/services/pages_service.dart';
import 'package:yovoice/features/pages/presentation/page_edit_copy.dart';
import 'package:yovoice/features/pages/presentation/page_profile_copy.dart';
import 'package:yovoice/features/pages/presentation/pages_copy.dart';
import 'package:yovoice/features/pages/presentation/screens/page_edit_screen.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_face.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_menus.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_profile_parts.dart';
import 'package:yovoice/features/profile/data/models/profile_visibility.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/settings/presentation/screens/profile_visibility_screen.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_filled_button.dart';
import 'package:yovoice/shared/widgets/buttons/yo_icon_button.dart';
import 'package:yovoice/shared/widgets/cards/yo_card.dart';
import 'package:yovoice/shared/widgets/identity/yo_vip_rosette.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';
import 'package:yovoice/shared/widgets/states/yo_loading_indicator.dart';

// The category and linked-server pickers lived here before "Edytuj stronę";
// they are re-exported so every existing import keeps resolving.
export 'package:yovoice/features/pages/presentation/widgets/page_pickers.dart';

/// Page settings (approved R6 `pages-r/settings/A_*`, spec premium-pages
/// §4.4; shortened by pageEdit A, owner decision 2026-10-03): the app's
/// Settings rows. The identity card with the status pill; STRONA with one
/// entry, "Edytuj stronę" (everything a visitor sees is edited there, in one
/// form with a live preview: [PageEditScreen]); OBSERWUJĄCY as a count only
/// (D12: no list); WIDOCZNOŚĆ STRONY with Wstrzymaj / Wznów; and the account
/// footnote.
///
/// Always a pushed screen (from the Page profile), so it carries its own
/// Back on every width; tablet and desktop centre one 640 column.
class PageSettingsScreen extends StatefulWidget {
  const PageSettingsScreen({
    this.service,
    this.accessStream,
    this.profileStream,
    this.userId,
    this.clock,
    this.editBuilder,
    super.key,
  });

  /// Test seams; the app uses the shared instances.
  final PagesService? service;
  final Stream<PageAccessState> Function()? accessStream;
  final Stream<UserProfile> Function()? profileStream;
  final String? userId;
  final DateTime Function()? clock;

  /// Builds "Edytuj stronę" (test seam).
  final WidgetBuilder? editBuilder;

  static const double columnWidth = 640;

  @override
  State<PageSettingsScreen> createState() => _PageSettingsScreenState();
}

class _PageSettingsScreenState extends State<PageSettingsScreen> {
  late final PagesService _service = widget.service ?? PagesService.instance;
  late final String _userId = widget.userId ?? _currentUserId();
  late final Stream<PageAccessState> _access =
      (widget.accessStream ?? PageAccessService.instance.watch)();
  late final Stream<UserProfile> _profile =
      (widget.profileStream ?? () => ProfileService().watchCurrentProfile())();

  bool _busy = false;

  static String _currentUserId() {
    try {
      return FirebaseAuth.instance.currentUser?.uid ?? '';
    } catch (_) {
      return '';
    }
  }

  PagesCopy get _copy => PagesCopy(AppLocalizations.of(context));

  void _snack(String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  // ------------------------------------------------------------- writes

  Future<void> _pause() async {
    final copy = _copy;
    final confirmed = await confirmPageAction(
      context,
      title: copy.pauseTitle,
      body: copy.pauseBody,
      confirm: copy.pause,
      cancel: copy.cancel,
      destructive: false,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await _service.pausePage();
      if (mounted) _snack(copy.pagePausedSnack);
    } on PagesException catch (error) {
      if (mounted) _snack(copy.manageError(error.failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resume() async {
    final copy = _copy;
    setState(() => _busy = true);
    try {
      await _service.resumePage();
      if (mounted) _snack(copy.pageResumedSnack);
    } on PagesException catch (error) {
      if (mounted) _snack(copy.manageError(error.failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openEdit() => unawaited(
    openPageEdit(
      context,
      builder:
          widget.editBuilder ??
          (_) => PageEditScreen(service: _service, userId: _userId),
    ),
  );

  void _openVisibility(UserProfile? profile) {
    unawaited(
      Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ProfileVisibilityScreen(
            initialVisibility:
                profile?.profileVisibility ?? ProfileVisibility.private,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = _copy;
    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        bottom: false,
        child: StreamBuilder<PageAccessState>(
          stream: _access,
          builder: (context, accessSnapshot) => StreamBuilder<UserProfile>(
            stream: _profile,
            builder: (context, profileSnapshot) {
              final access = accessSnapshot.data;
              final profile = profileSnapshot.hasError
                  ? null
                  : profileSnapshot.data;
              Widget body;
              if (accessSnapshot.hasError) {
                body = Padding(
                  padding: const EdgeInsets.only(top: 60),
                  child: YoErrorState(message: copy.loadSettingsError),
                );
              } else if (access == null || !access.resolved) {
                body = Padding(
                  padding: const EdgeInsets.only(top: 80),
                  child: Center(
                    child: YoLoadingIndicator(semanticLabel: copy.loadingPage),
                  ),
                );
              } else if (access.ownPage == null ||
                  access.ownPage!.kind == null) {
                body = Padding(
                  padding: const EdgeInsets.only(top: 60),
                  child: YoErrorState(message: copy.noPageYet),
                );
              } else {
                body = _content(context, access.ownPage!, profile);
              }
              // Desktop (the shell's wide content slot) has no status bar
              // above the title: give it the standard page top margin.
              final wide = MediaQuery.sizeOf(context).width >= 900;
              return ListView(
                key: const ValueKey('page-settings-list'),
                padding: EdgeInsets.only(top: wide ? 24 : 0),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: PageSettingsScreen.columnWidth + 32,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _TitleBar(
                            title: copy.pageSettings,
                            onBack: Navigator.of(context).canPop()
                                ? () => unawaited(
                                    Navigator.of(context).maybePop(),
                                  )
                                : null,
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
                            child: body,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  PageHeaderState _stateOf(OwnPage page) {
    if (page.suspended) return PageHeaderState.suspended;
    if (page.status == 'hidden') return PageHeaderState.hidden;
    if (page.ownerPaused) return PageHeaderState.paused;
    if (page.status == 'readOnly') return PageHeaderState.readOnly;
    return PageHeaderState.active;
  }

  Widget _content(BuildContext context, OwnPage page, UserProfile? profile) {
    final copy = _copy;
    final palette = context.appPalette;
    final kind = page.kind!;
    final state = _stateOf(page);
    final private =
        profile != null &&
        profile.profileVisibility != ProfileVisibility.public;
    final name = page.displayName ?? profile?.displayName ?? copy.yourPage;
    final categoryLabel = copy.categoryLabel(page.category);
    final pill = pageStatusPill(copy, state);

    Widget? notice;
    if (state == PageHeaderState.paused) {
      notice = private
          ? PageNotice(
              key: const ValueKey('settings-notice-private'),
              tone: PageTone.warning,
              icon: Icons.lock_outline_rounded,
              title: copy.pausedTitle,
              body: copy.pausedPrivateBody,
              actions: [
                PageTonalButton(
                  label: copy.profileVisibility,
                  icon: Icons.visibility_outlined,
                  height: 40,
                  onPressed: () => _openVisibility(profile),
                ),
              ],
            )
          : PageNotice(
              key: const ValueKey('settings-notice-paused'),
              tone: PageTone.info,
              icon: Icons.pause_circle_outline_rounded,
              title: copy.pausedTitle,
              body: copy.pausedBody,
              actions: [
                YoGradientFilledButton(
                  key: const ValueKey('settings-notice-resume'),
                  onPressed: _busy ? null : () => unawaited(_resume()),
                  minimumSize: const Size(64, 40),
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  child: Text(copy.resumePage),
                ),
              ],
            );
    } else if (state == PageHeaderState.suspended) {
      notice = PageNotice(
        tone: PageTone.danger,
        icon: Icons.gavel_rounded,
        title: copy.suspendedTitle,
        body: copy.suspendedBody(page.suspensionReason),
      );
    } else if (state == PageHeaderState.readOnly) {
      notice = PageNotice(
        tone: PageTone.warning,
        icon: Icons.hourglass_bottom_rounded,
        title: copy.readOnlyTitle,
        body: copy.readOnlyBody(),
      );
    } else if (state == PageHeaderState.hidden) {
      notice = PageNotice(
        tone: PageTone.neutral,
        icon: Icons.visibility_off_outlined,
        title: copy.hiddenTitle,
        body: copy.hiddenBody,
      );
    }

    // The account's own counter: a Page shares its follow edges with the
    // account (ADR-234), and `followerCount` is gated by the Creator audience
    // a Page always has switched off, so it would read 0 here.
    final followers = profile?.accountFollowerCount;
    return Column(
      key: const ValueKey('page-settings'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (notice != null) ...[notice, const SizedBox(height: 16)],
        YoCard(
          key: const ValueKey('settings-identity'),
          onTap: () => unawaited(Navigator.of(context).maybePop()),
          padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
          child: Row(
            children: [
              PageFace(pageId: _userId, name: name, kind: kind, size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NameWithVipMark(
                      uid: _userId,
                      name: name,
                      style: AppTypography.titleMedium.copyWith(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${copy.kindLabel(kind)} · $categoryLabel',
                      style: AppTypography.bodySmall.copyWith(
                        color: palette.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    PageStatusPill(
                      key: const ValueKey('settings-status'),
                      label: pill.label,
                      tone: pill.tone,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: palette.textTertiary),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _GroupLabel(copy.pageGroup),
        _SettingsGroup(
          children: [
            // Everything a visitor sees (cover, photo, name, category,
            // description, contact or rules and server) is one form now.
            // It opens in every state: a lapsed or suspended owner reads
            // the fields there and can still clear the contact details.
            _SettingsTile(
              key: const ValueKey('settings-edit'),
              icon: Icons.edit_outlined,
              title: copy.editPage,
              subtitle: copy.editPageSubtitle,
              chevron: true,
              enabled: !_busy,
              onTap: _openEdit,
            ),
          ],
        ),
        const SizedBox(height: 24),
        _GroupLabel(copy.followersGroup),
        _SettingsGroup(
          children: [
            _SettingsTile(
              key: const ValueKey('settings-followers'),
              icon: Icons.people_alt_outlined,
              title: followers == null
                  ? copy.followersGroup
                  : copy.exactFollowers(followers),
              subtitle: copy.followersOnlyCount,
            ),
          ],
        ),
        const SizedBox(height: 24),
        _GroupLabel(copy.visibilityGroup),
        _SettingsGroup(
          children: [
            if (!page.ownerPaused)
              _SettingsTile(
                key: const ValueKey('settings-pause'),
                icon: Icons.pause_circle_outline_rounded,
                title: copy.pausePage,
                subtitle: copy.pauseSubtitle,
                chevron: true,
                enabled: !_busy,
                onTap: () => unawaited(_pause()),
              )
            else
              _SettingsTile(
                key: const ValueKey('settings-resume'),
                icon: Icons.play_circle_outline_rounded,
                title: copy.resumePage,
                subtitle: private
                    ? copy.resumeNeedsPublic
                    : copy.resumeSubtitle,
                chevron: true,
                enabled: !private && !page.suspended && !_busy,
                onTap: () => unawaited(_resume()),
              ),
          ],
        ),
        PageFootnote(copy.accountFootnote, icon: Icons.person_outline_rounded),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Settings rows (the Settings screen's Slim tile and group)
// ---------------------------------------------------------------------------

class _TitleBar extends StatelessWidget {
  const _TitleBar({required this.title, required this.onBack});

  final String title;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = PagesCopy(AppLocalizations.of(context));
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        onBack == null ? 16 : 6,
        10,
        12,
        6,
      ),
      child: Row(
        children: [
          if (onBack != null) ...[
            YoIconButton(
              key: const ValueKey('page-settings-back'),
              icon: Icons.arrow_back_ios_new_rounded,
              iconSize: 18,
              size: 44,
              tooltip: copy.goBack,
              onPressed: onBack,
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.screenTitle.copyWith(
                  color: palette.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Semantics(
        header: true,
        child: Text(
          text.toUpperCase(),
          style: AppTypography.overline.copyWith(
            color: palette.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 11 * .08,
          ),
        ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final fill = AppFinish.blockFill(palette);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AppRadius.block,
        boxShadow: fill.boxShadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.block,
          side: BorderSide(color: palette.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(color: fill.color, gradient: fill.gradient),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    indent: 68,
                    color: palette.hairline,
                  ),
                children[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.chevron = false,
    this.enabled = true,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool chevron;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final tile = ListTile(
      minTileHeight: 64,
      contentPadding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
      minLeadingWidth: 40,
      horizontalTitleGap: 12,
      enabled: enabled,
      onTap: enabled ? onTap : null,
      leading: SizedBox.square(
        dimension: 40,
        child: Center(child: PageGlyph(icon)),
      ),
      title: Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.bodyLarge.copyWith(
          color: palette.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              // Room for the whole line at a large text size (the edit
              // entry's subtitle runs to four lines at 200 %).
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySmall.copyWith(
                color: palette.textSecondary,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
      trailing: chevron
          ? Icon(Icons.chevron_right_rounded, color: palette.textTertiary)
          : null,
    );
    return enabled || onTap == null ? tile : Opacity(opacity: .45, child: tile);
  }
}
