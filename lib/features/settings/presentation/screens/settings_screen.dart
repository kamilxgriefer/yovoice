import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:yovoice/shared/widgets/backgrounds/yo_page_background.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/preferences/app_preferences.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/shared/widgets/buttons/yo_icon_button.dart';
import 'package:yovoice/features/auth/data/auth_service.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/friends/presentation/screens/blocked_users_screen.dart';
import 'package:yovoice/features/marketing/data/services/public_showcase_consent_service.dart';
import 'package:yovoice/features/notifications/presentation/screens/notification_preferences_screen.dart';
import 'package:yovoice/features/permissions/presentation/permission_setup_sheet.dart';
import 'package:yovoice/features/premium/data/models/subscription_entitlements.dart';
import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/features/premium/presentation/screens/premium_plans_screen.dart';
import 'package:yovoice/features/premium/presentation/screens/premium_screen.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/models/profile_visibility.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/profile/presentation/screens/profile_screen.dart';
import 'package:yovoice/features/settings/presentation/screens/profile_visibility_screen.dart';
import 'package:yovoice/features/settings/presentation/screens/downloaded_audio_screen.dart';
import 'package:yovoice/features/settings/presentation/screens/device_sessions_screen.dart';
import 'package:yovoice/features/settings/presentation/screens/two_factor_authentication_screen.dart';
import 'package:yovoice/features/settings/presentation/widgets/appearance_language_settings_section.dart';
import 'package:yovoice/features/settings/presentation/widgets/message_privacy_settings_tile.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';
import 'package:yovoice/shared/widgets/states/yo_loading_indicator.dart';

Color _successForeground(BuildContext context) =>
    context.appPalette.successForeground;

Color _warningForeground(BuildContext context) =>
    context.appPalette.warningForeground;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    this.isRootTab = false,
    this.onReplayGuidedOnboarding,
    super.key,
  });

  /// True when this screen IS the shell's current content (a desktop
  /// content slot) rather than a pushed route — the same flag
  /// FriendsScreen uses, so a root tab never renders a back button that
  /// has nothing to pop.
  final bool isRootTab;

  /// Supplied by MainShell so replay can first leave this Settings route (or
  /// desktop slot), reveal stable navigation anchors, then show the tour.
  final Future<void> Function()? onReplayGuidedOnboarding;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _profileService = ProfileService();
  final _authService = AuthService();
  final _friendService = FriendService();
  final _entitlementService = EntitlementService();
  final _showcaseConsentService = PublicShowcaseConsentService();

  PackageInfo? _packageInfo;
  final Map<Permission, PermissionStatus> _permissionStatus = {};

  bool _sendingReset = false;
  bool _resendingVerification = false;
  bool _refreshingVerification = false;
  bool _clearingCache = false;
  bool _updatingShowcaseConsent = false;

  Future<void> _setShowcaseConsent({
    required UserProfile profile,
    required bool showProfile,
    required bool showActivity,
  }) async {
    if (_updatingShowcaseConsent) return;
    final copy = AppLocalizations.of(context);
    setState(() => _updatingShowcaseConsent = true);
    try {
      await _showcaseConsentService.setProfileConsent(
        userId: profile.uid,
        showProfile: showProfile,
        showActivity: showActivity,
      );
      _notify(
        showProfile
            ? copy.text(
                'Your public website showcase preferences were saved.',
                'Zapisano ustawienia prezentacji profilu na stronie.',
              )
            : copy.text(
                'Your profile will no longer appear in the website showcase.',
                'Twój profil nie będzie już wyświetlany na stronie.',
              ),
      );
    } catch (error) {
      _notify(
        copy.text(
          friendlyErrorMessage(error),
          'Nie udało się zapisać ustawień prezentacji profilu.',
        ),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _updatingShowcaseConsent = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
    _loadPermissionStatuses();
  }

  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _packageInfo = info);
  }

  Future<void> _loadPermissionStatuses() async {
    final results = await Future.wait([
      Permission.microphone.status,
      Permission.camera.status,
      Permission.notification.status,
    ]);
    if (!mounted) return;
    setState(() {
      _permissionStatus[Permission.microphone] = results[0];
      _permissionStatus[Permission.camera] = results[1];
      _permissionStatus[Permission.notification] = results[2];
    });
  }

  void _notify(String message, {bool isError = false}) {
    if (!mounted) return;
    final colors = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: isError ? TextStyle(color: colors.onErrorContainer) : null,
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError ? colors.errorContainer : null,
        ),
      );
  }

  Future<void> _setSoundEffectsEnabled(bool enabled) async {
    final copy = AppLocalizations.of(context);
    try {
      await AppPreferencesScope.of(context).setSoundEffectsEnabled(enabled);
    } catch (_) {
      _notify(
        copy.text(
          'Could not save the sound preference.',
          'Nie udało się zapisać ustawienia dźwięków.',
        ),
        isError: true,
      );
    }
  }

  Future<void> _openPermissionSetup() async {
    await showPermissionSetupSheet(
      context,
      userId: FirebaseAuth.instance.currentUser?.uid ?? '',
      recordSkip: false,
    );
    if (mounted) await _loadPermissionStatuses();
  }

  Future<void> _sendPasswordReset(String email) async {
    if (_sendingReset || email.isEmpty) return;
    final copy = AppLocalizations.of(context);
    setState(() => _sendingReset = true);
    try {
      await _authService.sendPasswordResetEmail(email);
      _notify(
        copy.text(
          'Password reset email sent to $email.',
          'Wiadomość z linkiem do zmiany hasła wysłano na $email.',
        ),
      );
    } catch (error) {
      _notify(
        copy.text(
          friendlyErrorMessage(error),
          'Nie udało się wysłać wiadomości do zmiany hasła. Spróbuj ponownie.',
        ),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _sendingReset = false);
    }
  }

  Future<void> _resendVerification() async {
    if (_resendingVerification) return;
    final copy = AppLocalizations.of(context);
    setState(() => _resendingVerification = true);
    try {
      await _authService.resendVerificationEmail();
      _notify(
        copy.text(
          'Verification email sent. Check your inbox.',
          'Wysłano wiadomość weryfikacyjną. Sprawdź skrzynkę odbiorczą.',
        ),
      );
    } catch (error) {
      _notify(
        copy.text(
          friendlyErrorMessage(error),
          'Nie udało się wysłać wiadomości weryfikacyjnej. Spróbuj ponownie.',
        ),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _resendingVerification = false);
    }
  }

  Future<void> _refreshVerification() async {
    if (_refreshingVerification) return;
    final copy = AppLocalizations.of(context);
    setState(() => _refreshingVerification = true);
    try {
      final verified = await _authService.reloadCurrentUser();
      _notify(
        verified
            ? copy.text(
                'Your email is verified.',
                'Adres e-mail jest zweryfikowany.',
              )
            : copy.text(
                'Still not verified — check your inbox for the link.',
                'Adres nadal nie jest zweryfikowany — sprawdź wiadomość z linkiem.',
              ),
        isError: !verified,
      );
      if (mounted) setState(() {});
    } catch (error) {
      _notify(
        copy.text(
          friendlyErrorMessage(error),
          'Nie udało się sprawdzić weryfikacji adresu e-mail. Spróbuj ponownie.',
        ),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _refreshingVerification = false);
    }
  }

  Future<void> _clearImageCache() async {
    if (_clearingCache) return;
    final copy = AppLocalizations.of(context);
    setState(() => _clearingCache = true);
    try {
      final bytesBefore = PaintingBinding.instance.imageCache.currentSizeBytes;
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      await Future.delayed(const Duration(milliseconds: 300));
      _notify(
        bytesBefore > 0
            ? copy.text(
                'Cleared ${_formatByteSize(bytesBefore)} of cached images.',
                'Usunięto ${_formatByteSize(bytesBefore)} obrazów z pamięci podręcznej.',
              )
            : copy.text(
                'Image cache was already empty.',
                'Pamięć podręczna obrazów była już pusta.',
              ),
      );
    } finally {
      if (mounted) setState(() => _clearingCache = false);
    }
  }

  Future<void> _openUrl(String url) async {
    final copy = AppLocalizations.of(context);
    final uri = Uri.parse(url);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      _notify(
        copy.text('Could not open $url', 'Nie udało się otworzyć $url'),
        isError: true,
      );
    }
  }

  Future<void> _confirmSignOut() async {
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final copy = AppLocalizations.of(dialogContext);
        final palette = dialogContext.appPalette;
        final colors = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          backgroundColor: palette.surfaceRaised,
          title: Text(
            copy.text('Log out?', 'Wylogować się?'),
            style: TextStyle(color: palette.textPrimary),
          ),
          content: Text(
            copy.text(
              'You will need to sign in again to use YO Voice.',
              'Aby ponownie korzystać z YO Voice, musisz się zalogować.',
            ),
            style: TextStyle(color: palette.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(copy.text('Cancel', 'Anuluj')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colors.errorContainer,
                foregroundColor: colors.onErrorContainer,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(copy.text('Log out', 'Wyloguj się')),
            ),
          ],
        );
      },
    );
    if (shouldSignOut == true) {
      await _authService.signOut();
    }
  }

  Future<void> _openDeleteAccountRequest() async {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.surfaceRaised,
      showDragHandle: false,
      constraints: ResponsiveContentFrame.adaptiveModalConstraints(
        context,
        maxWidth: 560,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 34),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            YoModalSheetChrome(
              sheetLabel: copy.text(
                'delete account request',
                'prośba o usunięcie konta',
              ),
              surfaceColor: palette.surfaceRaised,
            ),
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.errorContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.warning_rounded,
                color: colors.onErrorContainer,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              copy.text('Delete your account', 'Usuń swoje konto'),
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              copy.text(
                'Self-service account deletion isn\'t available yet. Email support and '
                    'we\'ll permanently delete your account, profile and content by hand.',
                'Samodzielne usuwanie konta nie jest jeszcze dostępne. Napisz do pomocy technicznej, '
                    'a trwale usuniemy Twoje konto, profil i treści.',
              ),
              style: TextStyle(
                color: palette.textSecondary,
                height: 1.45,
                fontSize: 13.5,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: colors.errorContainer,
                  foregroundColor: colors.onErrorContainer,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () {
                  Navigator.pop(sheetContext);
                  _openUrl(
                    'mailto:support@yovoice.app?subject=Delete%20my%20YO%20Voice%20account',
                  );
                },
                icon: const Icon(Icons.mail_outline_rounded),
                label: Text(
                  copy.text(
                    'Email support to delete my account',
                    'Napisz do pomocy technicznej, aby usunąć konto',
                  ),
                  maxLines: 2,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    return Scaffold(
      backgroundColor: palette.background,
      body: YoPageBackground(
        section: YoPageSection.more,
        child: SafeArea(
          child: ResponsiveContentFrame(
            width: ResponsiveContentWidth.list,
            alignment: ResponsiveContentAlignment.topLeft,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 10, 18, 6),
                  child: Row(
                    children: [
                      if (!widget.isRootTab) ...[
                        YoIconButton(
                          icon: Icons.arrow_back_ios_new_rounded,
                          iconSize: 18,
                          size: 40,
                          backgroundColor: palette.surface,
                          borderColor: palette.border,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        copy.text('Settings', 'Ustawienia'),
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: StreamBuilder<UserProfile>(
                    stream: _profileService.watchCurrentProfile(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return YoErrorState(
                          message: copy.text(
                            friendlyErrorMessage(snapshot.error!),
                            'Nie udało się wczytać ustawień. Spróbuj ponownie.',
                          ),
                          compact: true,
                        );
                      }
                      final profile = snapshot.data;
                      if (profile == null) {
                        return YoLoadingIndicator.fullscreen(
                          message: copy.text(
                            'Loading settings…',
                            'Ładowanie ustawień…',
                          ),
                        );
                      }
                      return _buildContent(context, profile);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, UserProfile profile) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final success = _successForeground(context);
    final emailVerified = _authService.currentUser?.emailVerified ?? false;

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 48),
      children: [
        // Identity editing lives on the Profile screen (its Edit button),
        // not in Settings — Settings is configuration, Profile is content.
        // The hero card is the doorway to that surface.
        _ProfileHeroCard(
          profile: profile,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const ProfileScreen()),
          ),
        ),
        const SizedBox(height: 22),

        _GroupLabel(copy.text('Account', 'Konto')),
        _SettingsGroup(
          children: [
            // Username and account type are read-only summaries here —
            // they're edited from Profile → Edit profile, the single
            // identity-editing surface.
            _SettingsTile(
              icon: Icons.alternate_email_rounded,
              title: copy.text('Username', 'Nazwa użytkownika'),
              subtitle: profile.username.isEmpty
                  ? copy.text('Not set', 'Nie ustawiono')
                  : '@${profile.username}',
            ),
            _SettingsTile(
              icon: Icons.mail_outline_rounded,
              title: copy.text('Email', 'E-mail'),
              subtitle: profile.email,
              trailing: _VerifiedChip(verified: emailVerified),
            ),
            _SettingsTile(
              icon: Icons.workspace_premium_outlined,
              title: copy.text('Account type', 'Typ konta'),
              subtitle: copy.text(
                profile.accountType.label,
                _polishAccountType(profile.accountType.label),
              ),
            ),
            _SettingsTile(
              icon: Icons.event_available_outlined,
              title: copy.text('Member since', 'Użytkownik od'),
              subtitle: _formatJoinDate(context, profile.createdAt),
            ),
          ],
        ),
        const SizedBox(height: 22),

        const _GroupLabel('YO Voice Premium'),
        StreamBuilder<SubscriptionEntitlements>(
          stream: _entitlementService.watchCurrentEntitlements(),
          builder: (context, snapshot) {
            final entitlements = snapshot.data ?? SubscriptionEntitlements.free;
            final periodEnd = entitlements.currentPeriodEnd;

            if (!entitlements.isPremium) {
              return _SettingsGroup(
                children: [
                  _SettingsTile(
                    icon: Icons.workspace_premium_outlined,
                    title: copy.text(
                      'Upgrade to Premium',
                      'Przejdź na Premium',
                    ),
                    subtitle: copy.text(
                      'Creator profile, Club creation and premium identity',
                      'Profil twórcy, tworzenie Klubów i wyjątkowy wygląd profilu',
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PremiumScreen(),
                      ),
                    ),
                  ),
                ],
              );
            }

            return _SettingsGroup(
              children: [
                _SettingsTile(
                  icon: Icons.workspace_premium_rounded,
                  title: copy.text(
                    'YO Voice Premium — ${entitlements.plan.label}',
                    'YO Voice Premium — ${_polishPlanLabel(entitlements.plan.label)}',
                  ),
                  subtitle: entitlements.inGracePeriod
                      ? copy.text(
                          'Payment issue — check your billing details',
                          'Problem z płatnością — sprawdź dane rozliczeniowe',
                        )
                      : periodEnd == null
                      ? copy.text('Active', 'Aktywne')
                      : copy.text(
                          'Active through ${periodEnd.day}.${periodEnd.month}.${periodEnd.year}',
                          'Aktywne do ${periodEnd.day}.${periodEnd.month}.${periodEnd.year}',
                        ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const PremiumScreen(),
                    ),
                  ),
                ),
                _SettingsTile(
                  icon: Icons.manage_accounts_outlined,
                  title: copy.text(
                    'Manage subscription',
                    'Zarządzaj subskrypcją',
                  ),
                  // The unified manager decides from trusted billing state
                  // whether this is Stripe, App Store, Play or an admin grant.
                  subtitle: kIsWeb
                      ? copy.text(
                          'Purchases and billing management',
                          'Zakupy i ustawienia płatności',
                        )
                      : copy.text(
                          'View your plan and billing options',
                          'Sprawdź plan i opcje płatności',
                        ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PremiumPlansScreen(),
                      ),
                    );
                  },
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 22),

        _GroupLabel(copy.text('Privacy', 'Prywatność')),
        _SettingsGroup(
          children: [
            StreamBuilder<List<Object?>>(
              stream: _friendService.watchBlockedUsers(),
              builder: (context, snapshot) {
                final count = snapshot.data?.length;
                return _SettingsTile(
                  icon: Icons.block_rounded,
                  title: copy.text('Blocked users', 'Zablokowane osoby'),
                  subtitle: count == null
                      ? copy.text(
                          'People you\'ve blocked',
                          'Osoby zablokowane przez Ciebie',
                        )
                      : count == 0
                      ? copy.text('No one blocked', 'Brak zablokowanych osób')
                      : copy.text(
                          '$count blocked',
                          'Zablokowane osoby: $count',
                        ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const BlockedUsersScreen(),
                    ),
                  ),
                );
              },
            ),
            _SettingsTile(
              icon: Icons.visibility_outlined,
              title: copy.text('Profile visibility', 'Widoczność profilu'),
              subtitle: _profileVisibilityLabel(
                context,
                profile.profileVisibility,
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ProfileVisibilityScreen(
                    initialVisibility: profile.profileVisibility,
                  ),
                ),
              ),
            ),
            StreamBuilder<PublicProfileShowcaseConsent>(
              stream: _showcaseConsentService.watchProfileConsent(profile.uid),
              initialData: const PublicProfileShowcaseConsent.hidden(),
              builder: (context, snapshot) {
                final consent =
                    snapshot.data ??
                    const PublicProfileShowcaseConsent.hidden();
                return Column(
                  children: [
                    _SettingsTile(
                      icon: Icons.public_rounded,
                      title: copy.text(
                        'Appear on the YO Voice website',
                        'Pokazuj profil na stronie YO Voice',
                      ),
                      subtitle: copy.text(
                        'Show your display name and profile type on the public internet, including to signed-out visitors and people you have blocked.',
                        'Wyświetlaj nazwę i typ profilu publicznie — także osobom niezalogowanym oraz zablokowanym przez Ciebie.',
                      ),
                      trailing: Switch.adaptive(
                        value: consent.showProfile,
                        onChanged: _updatingShowcaseConsent
                            ? null
                            : (value) => _setShowcaseConsent(
                                profile: profile,
                                showProfile: value,
                                showActivity: value && consent.showActivity,
                              ),
                      ),
                    ),
                    _SettingsTile(
                      icon: Icons.circle,
                      title: copy.text(
                        'Show my recent activity',
                        'Pokazuj ostatnią aktywność',
                      ),
                      subtitle: copy.text(
                        'May show “Active recently” after a fresh app heartbeat — never your last-seen time.',
                        'Może wyświetlać status „Ostatnio aktywny” po użyciu aplikacji — bez ujawniania dokładnego czasu aktywności.',
                      ),
                      trailing: Switch.adaptive(
                        value: consent.showActivity,
                        onChanged:
                            !consent.showProfile || _updatingShowcaseConsent
                            ? null
                            : (value) => _setShowcaseConsent(
                                profile: profile,
                                showProfile: true,
                                showActivity: value,
                              ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const MessagePrivacySettingsTile(),
          ],
        ),
        const SizedBox(height: 22),

        _GroupLabel(copy.text('Security', 'Bezpieczeństwo')),
        _SettingsGroup(
          children: [
            _SettingsTile(
              icon: Icons.lock_reset_rounded,
              title: copy.text('Reset password', 'Zmień hasło'),
              subtitle: copy.text(
                'Send a reset link to ${profile.email}',
                'Wyślij link do zmiany hasła na ${profile.email}',
              ),
              trailing: _sendingReset
                  ? _MiniSpinner(
                      semanticLabel: copy.text(
                        'Sending password reset email',
                        'Wysyłanie wiadomości do zmiany hasła',
                      ),
                    )
                  : Icon(
                      Icons.chevron_right_rounded,
                      color: palette.textTertiary,
                    ),
              onTap: _sendingReset
                  ? null
                  : () => _sendPasswordReset(profile.email),
            ),
            _SettingsTile(
              icon: emailVerified
                  ? Icons.verified_user_rounded
                  : Icons.gpp_maybe_rounded,
              title: copy.text('Email verification', 'Weryfikacja e-maila'),
              subtitle: emailVerified
                  ? copy.text(
                      'Your email is verified',
                      'Adres e-mail jest zweryfikowany',
                    )
                  : copy.text(
                      'Verify your email to unlock posting and rooms',
                      'Zweryfikuj adres e-mail, aby publikować i tworzyć pokoje',
                    ),
              trailing: emailVerified
                  ? Icon(Icons.check_circle_rounded, color: success)
                  : (_resendingVerification || _refreshingVerification)
                  ? _MiniSpinner(
                      semanticLabel: copy.text(
                        'Updating email verification',
                        'Aktualizowanie stanu weryfikacji e-maila',
                      ),
                    )
                  : Icon(
                      Icons.chevron_right_rounded,
                      color: palette.textTertiary,
                    ),
              onTap: emailVerified
                  ? null
                  : () => _showVerificationSheet(context),
            ),
            _SettingsTile(
              icon: Icons.security_rounded,
              title: copy.text(
                'Two-factor authentication',
                'Uwierzytelnianie dwuskładnikowe',
              ),
              subtitle: copy.text(
                'Use an authenticator code when you sign in',
                'Podczas logowania używaj kodu z aplikacji uwierzytelniającej',
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const TwoFactorAuthenticationScreen(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),

        _GroupLabel(copy.text('Notifications', 'Powiadomienia')),
        _SettingsGroup(
          children: [
            _SettingsTile(
              icon: Icons.notifications_active_outlined,
              title: copy.text(
                'Notification preferences',
                'Ustawienia powiadomień',
              ),
              subtitle: copy.text(
                'Choose what sends you a push notification',
                'Wybierz zdarzenia, o których chcesz otrzymywać powiadomienia',
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const NotificationPreferencesScreen(),
                ),
              ),
            ),
            _PermissionTile(
              icon: Icons.campaign_outlined,
              title: copy.text(
                'System notifications',
                'Powiadomienia systemowe',
              ),
              status: _permissionStatus[Permission.notification],
              onTap: _openPermissionSetup,
            ),
            _SettingsTile(
              icon: Icons.graphic_eq_rounded,
              title: copy.text('Sound effects', 'Dźwięki aplikacji'),
              subtitle: copy.text(
                'Room, microphone and in-app activity cues',
                'Sygnały dźwiękowe pokoi, mikrofonu i aktywności w aplikacji',
              ),
              trailing: Switch.adaptive(
                value: AppPreferencesScope.of(
                  context,
                ).value.soundEffectsEnabled,
                activeTrackColor: colors.primary,
                onChanged: _setSoundEffectsEnabled,
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),

        const AppearanceLanguageSettingsSection(),

        _GroupLabel(copy.text('Devices', 'Urządzenia')),
        _SettingsGroup(
          children: [
            _SettingsTile(
              icon: Icons.devices_rounded,
              title: copy.text('This device', 'To urządzenie'),
              subtitle: _deviceLabel(context),
              trailing: Icon(Icons.check_circle_rounded, color: success),
            ),
            _SettingsTile(
              icon: Icons.important_devices_outlined,
              title: copy.text('Devices & sessions', 'Urządzenia i sesje'),
              subtitle: copy.text(
                'Review this device or sign out everywhere',
                'Sprawdź to urządzenie lub wyloguj się wszędzie',
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const DeviceSessionsScreen(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),

        _GroupLabel(copy.text('Storage', 'Pamięć')),
        _SettingsGroup(
          children: [
            _SettingsTile(
              icon: Icons.cleaning_services_outlined,
              title: copy.text('Clear image cache', 'Wyczyść pamięć obrazów'),
              subtitle: _formatCacheSize(
                context,
                PaintingBinding.instance.imageCache.currentSizeBytes,
              ),
              trailing: _clearingCache
                  ? _MiniSpinner(
                      semanticLabel: copy.text(
                        'Clearing image cache',
                        'Czyszczenie pamięci obrazów',
                      ),
                    )
                  : Icon(
                      Icons.chevron_right_rounded,
                      color: palette.textTertiary,
                    ),
              onTap: _clearingCache ? null : _clearImageCache,
            ),
            _SettingsTile(
              icon: Icons.download_for_offline_outlined,
              title: copy.text('Downloaded audio', 'Pobrane nagrania'),
              subtitle: copy.text(
                'Manage offline Voice Moments',
                'Zarządzaj Voice Moments dostępnymi offline',
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const DownloadedAudioScreen(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),

        _GroupLabel(copy.text('Permissions', 'Uprawnienia')),
        _SettingsGroup(
          children: [
            _SettingsTile(
              icon: Icons.privacy_tip_outlined,
              title: copy.text(
                'Calls and alerts access',
                'Dostęp do połączeń i powiadomień',
              ),
              subtitle: copy.text(
                'Review notification, microphone and camera access',
                'Sprawdź dostęp do powiadomień, mikrofonu i aparatu',
              ),
              onTap: _openPermissionSetup,
            ),
            _PermissionTile(
              icon: Icons.mic_none_rounded,
              title: copy.text('Microphone', 'Mikrofon'),
              status: _permissionStatus[Permission.microphone],
              onTap: _openPermissionSetup,
            ),
            _PermissionTile(
              icon: Icons.photo_camera_outlined,
              title: copy.text('Camera', 'Aparat'),
              status: _permissionStatus[Permission.camera],
              onTap: _openPermissionSetup,
            ),
          ],
        ),
        const SizedBox(height: 22),

        _GroupLabel(copy.text('Help', 'Pomoc')),
        _SettingsGroup(
          children: [
            if (widget.onReplayGuidedOnboarding != null)
              _SettingsTile(
                icon: Icons.explore_outlined,
                title: copy.text('Quick app tour', 'Szybki przewodnik'),
                subtitle: copy.text(
                  'See the essentials again in five short steps',
                  'Zobacz najważniejsze funkcje w pięciu krótkich krokach',
                ),
                onTap: () => unawaited(widget.onReplayGuidedOnboarding!.call()),
              ),
            _SettingsTile(
              icon: Icons.help_outline_rounded,
              title: copy.text('Help center', 'Centrum pomocy'),
              subtitle: copy.text(
                'Guides and answers to common questions',
                'Poradniki i odpowiedzi na najczęstsze pytania',
              ),
              onTap: () => _openUrl('https://yovoice.app/help-center'),
            ),
            _SettingsTile(
              icon: Icons.support_agent_rounded,
              title: copy.text('Contact support', 'Skontaktuj się z pomocą'),
              subtitle: 'support@yovoice.app',
              onTap: () => _openUrl('mailto:support@yovoice.app'),
            ),
          ],
        ),
        const SizedBox(height: 22),

        _GroupLabel(copy.text('About', 'O aplikacji')),
        _SettingsGroup(
          children: [
            _SettingsTile(
              icon: Icons.info_outline_rounded,
              title: copy.text('Version', 'Wersja'),
              subtitle: _packageInfo == null
                  ? copy.text('Loading…', 'Ładowanie…')
                  : '${_packageInfo!.version} (${_packageInfo!.buildNumber})',
            ),
            _SettingsTile(
              icon: Icons.language_rounded,
              title: copy.text('Visit yovoice.app', 'Odwiedź yovoice.app'),
              subtitle: copy.text('Our website', 'Nasza strona internetowa'),
              onTap: () => _openUrl('https://yovoice.app'),
            ),
          ],
        ),
        const SizedBox(height: 22),

        _GroupLabel(copy.text('Legal', 'Informacje prawne')),
        _SettingsGroup(
          children: [
            _SettingsTile(
              icon: Icons.privacy_tip_outlined,
              title: copy.text('Privacy policy', 'Polityka prywatności'),
              onTap: () => _openUrl('https://yovoice.app/privacy'),
            ),
            _SettingsTile(
              icon: Icons.gavel_rounded,
              title: copy.text('Terms of service', 'Warunki korzystania'),
              onTap: () => _openUrl('https://yovoice.app/terms'),
            ),
          ],
        ),
        const SizedBox(height: 22),

        _GroupLabel(
          copy.text('Danger zone', 'Strefa niebezpieczna'),
          danger: true,
        ),
        _SettingsGroup(
          danger: true,
          children: [
            _SettingsTile(
              icon: Icons.logout_rounded,
              title: copy.text('Log out', 'Wyloguj się'),
              danger: true,
              onTap: _confirmSignOut,
            ),
            _SettingsTile(
              icon: Icons.delete_forever_rounded,
              title: copy.text('Delete account', 'Usuń konto'),
              subtitle: copy.text(
                'Permanently remove your account and data',
                'Trwale usuń konto i wszystkie dane',
              ),
              danger: true,
              onTap: _openDeleteAccountRequest,
            ),
          ],
        ),
      ],
    );
  }

  void _showVerificationSheet(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.surfaceRaised,
      showDragHandle: false,
      constraints: ResponsiveContentFrame.adaptiveModalConstraints(
        context,
        maxWidth: 560,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 34),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              YoModalSheetChrome(
                sheetLabel: copy.text(
                  'email verification',
                  'weryfikacja adresu e-mail',
                ),
                surfaceColor: palette.surfaceRaised,
              ),
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.mark_email_unread_rounded,
                  color: colors.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                copy.text('Verify your email', 'Zweryfikuj adres e-mail'),
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                copy.text(
                  'Check your inbox for the verification link, then come back and refresh.',
                  'Sprawdź wiadomość z linkiem weryfikacyjnym, a następnie wróć tutaj i odśwież status.',
                ),
                style: TextStyle(
                  color: palette.textSecondary,
                  height: 1.45,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, constraints) {
                  final vertical =
                      constraints.maxWidth < 420 ||
                      MediaQuery.textScalerOf(context).scale(1) > 1.3;
                  final resend = OutlinedButton(
                    onPressed: _resendingVerification
                        ? null
                        : () async {
                            await _resendVerification();
                          },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: palette.textPrimary,
                      side: BorderSide(color: palette.border),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _resendingVerification
                        ? _MiniSpinner(
                            semanticLabel: copy.text(
                              'Resending verification email',
                              'Ponowne wysyłanie wiadomości weryfikacyjnej',
                            ),
                          )
                        : Text(copy.text('Resend email', 'Wyślij ponownie')),
                  );
                  final verified = FilledButton(
                    onPressed: _refreshingVerification
                        ? null
                        : () async {
                            await _refreshVerification();
                            if (context.mounted) Navigator.pop(sheetContext);
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: colors.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _refreshingVerification
                        ? _MiniSpinner(
                            color: colors.onPrimary,
                            semanticLabel: copy.text(
                              'Checking email verification',
                              'Sprawdzanie weryfikacji adresu e-mail',
                            ),
                          )
                        : Text(
                            copy.text('I\'ve verified', 'Adres zweryfikowany'),
                          ),
                  );
                  if (vertical) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [resend, const SizedBox(height: 10), verified],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: resend),
                      const SizedBox(width: 10),
                      Expanded(child: verified),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatJoinDate(BuildContext context, DateTime? date) {
    final copy = AppLocalizations.of(context);
    if (date == null) return copy.text('Unknown', 'Nieznana data');
    final months = [
      copy.text('January', 'stycznia'),
      copy.text('February', 'lutego'),
      copy.text('March', 'marca'),
      copy.text('April', 'kwietnia'),
      copy.text('May', 'maja'),
      copy.text('June', 'czerwca'),
      copy.text('July', 'lipca'),
      copy.text('August', 'sierpnia'),
      copy.text('September', 'września'),
      copy.text('October', 'października'),
      copy.text('November', 'listopada'),
      copy.text('December', 'grudnia'),
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  String _deviceLabel(BuildContext context) {
    final copy = AppLocalizations.of(context);
    if (kIsWeb) return copy.text('Web browser', 'Przeglądarka internetowa');
    if (Platform.isIOS) return copy.text('iOS device', 'Urządzenie z iOS');
    if (Platform.isAndroid) {
      return copy.text('Android device', 'Urządzenie z Androidem');
    }
    if (Platform.isMacOS) return copy.text('macOS device', 'Komputer Mac');
    if (Platform.isWindows) {
      return copy.text('Windows device', 'Komputer z Windows');
    }
    if (Platform.isLinux) {
      return copy.text('Linux device', 'Komputer z Linuxem');
    }
    return copy.text('This device', 'To urządzenie');
  }

  String _formatCacheSize(BuildContext context, int bytes) {
    final copy = AppLocalizations.of(context);
    if (bytes <= 0) {
      return copy.text('Nothing cached', 'Pamięć podręczna jest pusta');
    }
    final size = _formatByteSize(bytes);
    return copy.text('$size cached', 'W pamięci podręcznej: $size');
  }
}

String _formatByteSize(int bytes) {
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _polishAccountType(String label) => switch (label.toLowerCase()) {
  'creator' => 'Twórca',
  'business' => 'Firma',
  'user' || 'member' => 'Użytkownik',
  _ => label,
};

String _polishPlanLabel(String label) => switch (label.toLowerCase()) {
  'monthly' => 'miesięczny',
  'annual' || 'yearly' => 'roczny',
  'lifetime' => 'dożywotni',
  _ => label,
};

String _profileVisibilityLabel(
  BuildContext context,
  ProfileVisibility visibility,
) {
  final copy = AppLocalizations.of(context);
  return switch (visibility) {
    ProfileVisibility.public => copy.text('Everyone', 'Wszyscy'),
    ProfileVisibility.friends => copy.text('Friends only', 'Tylko znajomi'),
    ProfileVisibility.private => copy.text('Only me', 'Tylko ja'),
  };
}

class _ProfileHeroCard extends StatelessWidget {
  const _ProfileHeroCard({required this.profile, required this.onTap});

  final UserProfile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final avatar = profile.photoUrl?.trim();
    final expanded = MediaQuery.textScalerOf(context).scale(1) >= 1.6;
    return Semantics(
      button: true,
      label: copy.text(
        'Open profile for ${profile.displayName}. Edit profile details and photos.',
        'Otwórz profil użytkownika ${profile.displayName}. Edytuj dane profilu i zdjęcia.',
      ),
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: palette.surface,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              crossAxisAlignment: expanded
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [colors.primary, colors.secondary],
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 30,
                    backgroundColor: colors.primary,
                    backgroundImage: avatar?.isNotEmpty == true
                        ? NetworkImage(avatar!)
                        : null,
                    child: avatar?.isNotEmpty == true
                        ? null
                        : Text(
                            profile.displayName.isEmpty
                                ? '?'
                                : profile.displayName[0].toUpperCase(),
                            style: TextStyle(
                              color: colors.onPrimary,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.displayName,
                        maxLines: expanded ? 3 : 1,
                        overflow: expanded
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        copy.text(
                          'Edit profile details and photos',
                          'Edytuj dane profilu i zdjęcia',
                        ),
                        maxLines: expanded ? null : 2,
                        overflow: expanded
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: EdgeInsets.only(top: expanded ? 8 : 0),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: palette.textTertiary,
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

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text, {this.danger = false});
  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            color: danger
                ? Theme.of(context).colorScheme.error
                : palette.textSecondary,
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children, this.danger = false});
  final List<Widget> children;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: danger ? colors.error.withValues(alpha: .45) : palette.border,
        ),
      ),
      child: Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0)
              Divider(
                height: 1,
                indent: 56,
                endIndent: 16,
                color: palette.border,
              ),
            children[index],
          ],
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final iconColor = danger ? colors.error : colors.primary;
    final titleColor = danger ? colors.error : palette.textPrimary;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final expanded = textScale >= 1.6;
    final effectiveTrailing =
        trailing ??
        (onTap != null
            ? Icon(Icons.chevron_right_rounded, color: palette.textTertiary)
            : null);
    final stackTrailing =
        expanded && effectiveTrailing != null && effectiveTrailing is! Icon;
    final subtitleWidget = subtitle == null
        ? null
        : Text(
            subtitle!,
            maxLines: expanded ? null : 3,
            overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            style: TextStyle(color: palette.textSecondary, fontSize: 12),
          );

    return MergeSemantics(
      child: ListTile(
        minTileHeight: 64,
        titleAlignment: expanded
            ? ListTileTitleAlignment.top
            : ListTileTitleAlignment.center,
        onTap: onTap,
        leading: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: .14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        title: Text(
          title,
          maxLines: expanded ? null : 2,
          overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          style: TextStyle(
            color: titleColor,
            fontWeight: FontWeight.w700,
            fontSize: 14.5,
          ),
        ),
        subtitle: !stackTrailing
            ? subtitleWidget
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ?subtitleWidget,
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: effectiveTrailing,
                  ),
                ],
              ),
        trailing: stackTrailing ? null : effectiveTrailing,
      ),
    );
  }
}

class _VerifiedChip extends StatelessWidget {
  const _VerifiedChip({required this.verified});
  final bool verified;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final foreground = verified
        ? _successForeground(context)
        : _warningForeground(context);
    final surface = verified ? palette.successSurface : palette.warningSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: Color.alphaBlend(
            foreground.withValues(alpha: .38),
            palette.border,
          ),
        ),
      ),
      child: Text(
        verified
            ? copy.text('VERIFIED', 'ZWERYFIKOWANO')
            : copy.text('UNVERIFIED', 'NIEZWERYFIKOWANO'),
        style: TextStyle(
          color: foreground,
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
          letterSpacing: .4,
        ),
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.icon,
    required this.title,
    required this.status,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final PermissionStatus? status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final label = switch (status) {
      null => copy.text('Checking…', 'Sprawdzanie…'),
      PermissionStatus.granted ||
      PermissionStatus.limited => copy.text('Allowed', 'Zezwolono'),
      PermissionStatus.permanentlyDenied => copy.text(
        'Denied — open settings',
        'Odmówiono — otwórz ustawienia',
      ),
      PermissionStatus.denied => copy.text('Not allowed', 'Brak zezwolenia'),
      PermissionStatus.restricted => copy.text('Restricted', 'Ograniczono'),
      PermissionStatus.provisional => copy.text('Provisional', 'Tymczasowo'),
    };
    final granted =
        status == PermissionStatus.granted ||
        status == PermissionStatus.limited;

    return _SettingsTile(
      icon: icon,
      title: title,
      subtitle: label,
      trailing: granted
          ? Icon(Icons.check_circle_rounded, color: _successForeground(context))
          : Icon(Icons.chevron_right_rounded, color: palette.textTertiary),
      onTap: onTap,
    );
  }
}

class _MiniSpinner extends StatelessWidget {
  const _MiniSpinner({this.color, required this.semanticLabel});

  final Color? color;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: color ?? Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }
}
