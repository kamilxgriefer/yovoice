import 'package:flutter/material.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/premium/data/models/subscription_entitlements.dart';
import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/features/premium/presentation/screens/premium_screen.dart';
import 'package:yovoice/features/messages/data/models/premium_messaging_privacy.dart';
import 'package:yovoice/features/settings/data/services/premium_messaging_privacy_service.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';
import 'package:yovoice/shared/widgets/states/yo_loading_indicator.dart';

class PremiumMessagingPrivacyScreen extends StatefulWidget {
  const PremiumMessagingPrivacyScreen({
    this.service,
    this.entitlementStream,
    super.key,
  });

  final PremiumMessagingPrivacyGateway? service;
  final Stream<SubscriptionEntitlements>? entitlementStream;

  @override
  State<PremiumMessagingPrivacyScreen> createState() =>
      _PremiumMessagingPrivacyScreenState();
}

class _PremiumMessagingPrivacyScreenState
    extends State<PremiumMessagingPrivacyScreen> {
  late final PremiumMessagingPrivacyGateway _service =
      widget.service ?? PremiumMessagingPrivacyService();
  late Stream<SubscriptionEntitlements> _entitlements =
      widget.entitlementStream ??
      EntitlementService().watchCurrentEntitlements();
  late Stream<PremiumMessagingPrivacy> _privacy = _service.watchCurrent();
  PremiumMessagingPrivacyPreference? _saving;
  String? _saveError;

  void _retry() {
    setState(() {
      _saveError = null;
      _privacy = _service.watchCurrent();
    });
  }

  void _retryPremiumAccess() {
    setState(() {
      _entitlements =
          widget.entitlementStream ??
          EntitlementService().watchCurrentEntitlements();
    });
  }

  Future<void> _set(
    PremiumMessagingPrivacyPreference preference,
    bool enabled,
  ) async {
    if (_saving != null) return;
    setState(() {
      _saving = preference;
      _saveError = null;
    });
    try {
      await _service.setPreference(preference, enabled);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saveError = friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    return Scaffold(
      key: const ValueKey('premium-messaging-privacy-screen'),
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        foregroundColor: palette.textPrimary,
        title: Text(copy.text('Chat privacy', 'Prywatność czatu')),
      ),
      body: SafeArea(
        top: false,
        child: ResponsiveContentFrame(
          width: ResponsiveContentWidth.form,
          padding: ResponsiveContentFrame.adaptivePagePadding(
            MediaQuery.sizeOf(context).width,
          ),
          child: StreamBuilder<SubscriptionEntitlements>(
            stream: _entitlements,
            builder: (context, entitlementSnapshot) {
              if (entitlementSnapshot.hasError) {
                return Center(
                  child: YoErrorState(
                    message: copy.text(
                      'Could not check Premium access.',
                      'Nie udało się sprawdzić dostępu Premium.',
                    ),
                    onRetry: _retryPremiumAccess,
                  ),
                );
              }
              if (entitlementSnapshot.connectionState ==
                      ConnectionState.waiting &&
                  !entitlementSnapshot.hasData) {
                return YoLoadingIndicator.fullscreen(
                  message: copy.text(
                    'Checking Premium access…',
                    'Sprawdzamy dostęp Premium…',
                  ),
                );
              }
              final premium = entitlementSnapshot.data?.isPremium == true;
              return StreamBuilder<PremiumMessagingPrivacy>(
                stream: _privacy,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: YoErrorState(
                        message: copy.text(
                          friendlyErrorMessage(snapshot.error!),
                          'Nie udało się wczytać ustawień prywatności czatu.',
                        ),
                        onRetry: _retry,
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return YoLoadingIndicator.fullscreen(
                      message: copy.text(
                        'Loading chat privacy…',
                        'Ładowanie prywatności czatu…',
                      ),
                    );
                  }
                  return _PrivacyContent(
                    privacy: snapshot.data!,
                    premium: premium,
                    saving: _saving,
                    saveError: _saveError,
                    onChanged: _set,
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

class _PrivacyContent extends StatelessWidget {
  const _PrivacyContent({
    required this.privacy,
    required this.premium,
    required this.saving,
    required this.saveError,
    required this.onChanged,
  });

  final PremiumMessagingPrivacy privacy;
  final bool premium;
  final PremiumMessagingPrivacyPreference? saving;
  final String? saveError;
  final Future<void> Function(
    PremiumMessagingPrivacyPreference preference,
    bool enabled,
  )
  onChanged;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 640;
        final controls = <Widget>[
          _PrivacyControlCard(
            key: const ValueKey('hide-read-receipts-control'),
            icon: Icons.visibility_off_rounded,
            title: copy.text('Incognito reads', 'Odczyty incognito'),
            description: copy.text(
              'Open messages without sending a read receipt. Your unread badge still clears.',
              'Otwieraj wiadomości bez wysyłania potwierdzenia odczytu. Licznik nieprzeczytanych nadal znika.',
            ),
            value: privacy.hideReadReceipts,
            effective: premium && privacy.hideReadReceipts,
            savedButInactive: !premium && privacy.hideReadReceipts,
            enabled: saving == null && (premium || privacy.hideReadReceipts),
            saving:
                saving == PremiumMessagingPrivacyPreference.hideReadReceipts,
            onChanged: (value) => onChanged(
              PremiumMessagingPrivacyPreference.hideReadReceipts,
              value,
            ),
          ),
          _PrivacyControlCard(
            key: const ValueKey('hide-typing-control'),
            icon: Icons.keyboard_hide_rounded,
            title: copy.text('Hide typing', 'Ukryj pisanie'),
            description: copy.text(
              'People in private chats will not see when you are typing.',
              'Osoby w prywatnych czatach nie zobaczą, kiedy piszesz.',
            ),
            value: privacy.hideTyping,
            effective: premium && privacy.hideTyping,
            savedButInactive: !premium && privacy.hideTyping,
            enabled: saving == null && (premium || privacy.hideTyping),
            saving: saving == PremiumMessagingPrivacyPreference.hideTyping,
            onChanged: (value) =>
                onChanged(PremiumMessagingPrivacyPreference.hideTyping, value),
          ),
        ];
        return ListView(
          padding: const EdgeInsets.fromLTRB(0, 20, 0, 40),
          children: [
            Text(
              copy.text(
                'Your presence, your choice',
                'Twoja obecność, Twój wybór',
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
                'Read receipts and typing visibility are controlled separately.',
                'Potwierdzenia odczytu i widoczność pisania ustawiasz osobno.',
              ),
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 14,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            if (!premium) ...[
              Container(
                key: const ValueKey('premium-privacy-locked'),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: colors.primaryContainer.withValues(alpha: .6),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: colors.primary.withValues(alpha: .5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.workspace_premium_rounded,
                          color: colors.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            copy.text(
                              'Included with YO Voice Premium',
                              'Dostępne w YO Voice Premium',
                            ),
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      copy.text(
                        'Choose when read receipts and typing status are shared in private chats.',
                        'Decyduj, kiedy potwierdzenia odczytu i status pisania są widoczne w prywatnych czatach.',
                      ),
                      style: TextStyle(
                        color: palette.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      key: const ValueKey('open-premium-from-privacy'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const PremiumScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.auto_awesome_rounded),
                      label: Text(copy.text('See Premium', 'Zobacz Premium')),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: controls[0]),
                  const SizedBox(width: 14),
                  Expanded(child: controls[1]),
                ],
              )
            else ...[
              controls[0],
              const SizedBox(height: 12),
              controls[1],
            ],
            if (saveError != null) ...[
              const SizedBox(height: 14),
              Semantics(
                liveRegion: true,
                child: Text(
                  copy.text(
                    'Could not save this setting. $saveError',
                    'Nie udało się zapisać ustawienia. Spróbuj ponownie.',
                  ),
                  key: const ValueKey('premium-privacy-save-error'),
                  style: TextStyle(
                    color: colors.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
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
                  Icon(Icons.shield_outlined, color: colors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      copy.text(
                        'Incognito clears your own unread badge without sending a receipt. When you turn it off, earlier hidden reads stay hidden and only later reads can send receipts.',
                        'Incognito usuwa Twój licznik nieprzeczytanych bez wysyłania potwierdzenia. Po wyłączeniu wcześniejsze ukryte odczyty pozostają ukryte, a potwierdzenia mogą dotyczyć dopiero kolejnych odczytów.',
                      ),
                      style: TextStyle(
                        color: palette.textSecondary,
                        height: 1.4,
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
  }
}

class _PrivacyControlCard extends StatelessWidget {
  const _PrivacyControlCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.value,
    required this.effective,
    required this.savedButInactive,
    required this.enabled,
    required this.saving,
    required this.onChanged,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool value;
  final bool effective;
  final bool savedButInactive;
  final bool enabled;
  final bool saving;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 112),
      child: Material(
        color: palette.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: effective ? colors.primary : palette.border),
        ),
        child: SwitchListTile.adaptive(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 10,
          ),
          secondary: Icon(
            icon,
            color: effective ? colors.primary : palette.textTertiary,
          ),
          title: Text(
            title,
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              savedButInactive
                  ? '$description\n${AppLocalizations.of(context).text('Saved, but inactive without Premium.', 'Zapisane, ale nieaktywne bez Premium.')}'
                  : description,
              style: TextStyle(color: palette.textSecondary, height: 1.35),
            ),
          ),
          value: value,
          onChanged: enabled && !saving ? onChanged : null,
        ),
      ),
    );
  }
}
