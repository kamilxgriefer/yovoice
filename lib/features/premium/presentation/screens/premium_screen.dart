import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/premium/data/models/subscription_entitlements.dart';
import 'package:yovoice/features/premium/data/premium_plans.dart';
import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/features/premium/data/services/premium_billing_service.dart';
import 'package:yovoice/features/premium/presentation/screens/premium_plans_screen.dart';
import 'package:yovoice/features/premium/presentation/widgets/premium_badge_pill.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/shared/widgets/profile/premium_avatar_frame.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

const _premiumGradientColors = [AppColors.primary, Color(0xFFB020E8)];

/// The YO Voice Premium presentation — what a free member sees when they
/// open Premium. Marketing surface only: the "Check plans" CTA leads to
/// [PremiumPlansScreen], where the real plans and purchase entry points
/// live. Because this screen watches the entitlement stream, it is also
/// the success state: the moment the TRUSTED entitlements document turns
/// premium, the presentation flips to [_PremiumActiveView] — which makes
/// it the natural landing after an admin grant or a future real purchase.
///
/// The hero is the signed-in member's REAL avatar (canonical [UserAvatar]
/// via [ProfileService]) wearing the canonical [PremiumAvatarFrame] —
/// a truthful preview of their own Premium identity, never a fake person.
class PremiumScreen extends StatefulWidget {
  const PremiumScreen({
    this.entitlementService,
    this.profileService,
    this.billingService,
    super.key,
  });

  final EntitlementService? entitlementService;
  final ProfileService? profileService;
  final PremiumBillingGateway? billingService;

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  late final EntitlementService _entitlements =
      widget.entitlementService ?? EntitlementService();
  late final ProfileService _profiles =
      widget.profileService ?? ProfileService();

  bool _wasPremiumOnOpen = false;
  bool _checkedInitial = false;

  void _openPlans() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PremiumPlansScreen(
          entitlementService: widget.entitlementService,
          billingService: widget.billingService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: palette.textPrimary,
        elevation: 0,
      ),
      body: StreamBuilder<SubscriptionEntitlements>(
        stream: _entitlements.watchCurrentEntitlements(),
        builder: (context, snapshot) {
          final entitlements = snapshot.data ?? SubscriptionEntitlements.free;

          // Remember whether the user ARRIVED premium, so the success
          // celebration only plays for a transition that happened while
          // this screen was open.
          if (!_checkedInitial && snapshot.hasData) {
            _wasPremiumOnOpen = entitlements.isPremium;
            _checkedInitial = true;
          }

          if (entitlements.isPremium) {
            return _PremiumActiveView(
              entitlements: entitlements,
              justActivated: _checkedInitial && !_wasPremiumOnOpen,
              onManageSubscription: _openPlans,
            );
          }

          return _PremiumPresentationView(
            profileStream: _profiles.watchCurrentProfile(),
            onCheckPlans: _openPlans,
          );
        },
      ),
    );
  }
}

/// Board screen 3: badge pill, headline, real-identity hero, the three
/// benefit cards, and the "Check plans" CTA.
class _PremiumPresentationView extends StatelessWidget {
  const _PremiumPresentationView({
    required this.profileStream,
    required this.onCheckPlans,
  });

  final Stream<UserProfile> profileStream;
  final VoidCallback onCheckPlans;

  static const _benefitIcons = [
    (Icons.mic_rounded, Color(0xFFD3A5FF)),
    (Icons.workspace_premium_rounded, Color(0xFFFFC24D)),
    (Icons.auto_awesome_rounded, Color(0xFFE879F9)),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 40),
          children: [
            const Center(child: PremiumBadgePill()),
            const SizedBox(height: 18),
            Text(
              'More room\nfor your voice.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 32,
                height: 1.12,
                fontWeight: FontWeight.w900,
                letterSpacing: -.8,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Create. Lead. Build communities.\nStand out.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 14.5,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 10),
            StreamBuilder<UserProfile>(
              stream: profileStream,
              builder: (context, snapshot) =>
                  _PremiumHero(profile: snapshot.data),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final cards = [
                  for (var i = 0; i < PremiumPlans.benefits.length; i++)
                    _BenefitCard(
                      icon: _benefitIcons[i].$1,
                      iconColor: _benefitIcons[i].$2,
                      title: PremiumPlans.benefits[i].$1,
                      subtitle: PremiumPlans.benefits[i].$2,
                    ),
                ];
                final stacked =
                    constraints.maxWidth < 420 ||
                    MediaQuery.textScalerOf(context).scale(1) > 1.3;
                if (stacked) {
                  return Column(
                    children: [
                      for (var i = 0; i < cards.length; i++) ...[
                        if (i > 0) const SizedBox(height: 10),
                        cards[i],
                      ],
                    ],
                  );
                }
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < cards.length; i++) ...[
                        if (i > 0) const SizedBox(width: 10),
                        Expanded(child: cards[i]),
                      ],
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 26),
            _CheckPlansButton(onTap: onCheckPlans),
          ],
        ),
      ),
    );
  }
}

/// The Premium identity hero: the member's own avatar inside the
/// canonical premium ring, lifted by a presentation-only backdrop glow,
/// crown chip and capability pills. Wraps [UserAvatar] — this is a
/// presentation shell, never a second avatar implementation.
class _PremiumHero extends StatelessWidget {
  const _PremiumHero({required this.profile});

  final UserProfile? profile;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(340.0, constraints.maxWidth);
        const height = 290.0;
        const avatarRadius = 72.0;
        const ringWidth = 4.2;
        const ringGap = 8.0;
        // PremiumAvatarFrame inset: ringWidth + gap on every side.
        const framedRadius = avatarRadius + ringWidth + ringGap;

        // Crown chip sits on the ring's top-right diagonal.
        const chipSize = 40.0;
        final chipOffset = framedRadius * math.sqrt2 / 2;

        return Center(
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          colors: [
                            AppColors.secondary.withValues(alpha: .30),
                            AppColors.primary.withValues(alpha: .14),
                            Colors.transparent,
                          ],
                          stops: const [0, .45, 1],
                        ),
                      ),
                    ),
                  ),
                ),
                // Bloom behind the ring — the presentation-strength glow
                // the canonical frame deliberately keeps subtle elsewhere.
                IgnorePointer(
                  child: Container(
                    width: framedRadius * 2,
                    height: framedRadius * 2,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.secondary.withValues(alpha: .42),
                          blurRadius: 52,
                          spreadRadius: 8,
                        ),
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: .30),
                          blurRadius: 90,
                          spreadRadius: 26,
                        ),
                      ],
                    ),
                  ),
                ),
                PremiumAvatarFrame(
                  ringWidth: ringWidth,
                  gap: ringGap,
                  child: UserAvatar(
                    radius: avatarRadius,
                    photoUrl: profile?.photoUrl,
                    displayName: profile?.displayName,
                    fallbackIcon: Icons.graphic_eq_rounded,
                  ),
                ),
                Positioned(
                  left: width / 2 + chipOffset - chipSize / 2,
                  top: height / 2 - chipOffset - chipSize / 2,
                  child: const _CrownChip(size: chipSize),
                ),
                const Positioned(
                  left: 0,
                  top: height / 2 + 28,
                  child: _HeroPill(
                    icon: Icons.groups_rounded,
                    label: 'Club Owner',
                  ),
                ),
                const Positioned(
                  right: 0,
                  top: height / 2 - 58,
                  child: _HeroPill(icon: Icons.mic_rounded, label: 'Creator'),
                ),
                Positioned(
                  bottom: 4,
                  right: width * .12,
                  child: const _HeroPill(
                    icon: Icons.auto_awesome_rounded,
                    label: 'Premium Identity',
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CrownChip extends StatelessWidget {
  const _CrownChip({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _premiumGradientColors,
        ),
        border: Border.all(color: Colors.white.withValues(alpha: .22)),
        boxShadow: [
          BoxShadow(
            color: AppColors.secondary.withValues(alpha: .5),
            blurRadius: 16,
          ),
        ],
      ),
      child: Icon(
        Icons.workspace_premium_rounded,
        size: size * .55,
        color: Colors.white,
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: palette.surfaceRaised,
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: .18),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        runSpacing: 3,
        children: [
          Icon(icon, size: 13, color: colors.primary),
          Text(
            label,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _BenefitCard extends StatelessWidget {
  const _BenefitCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 18, 10, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: palette.surface,
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 26, color: iconColor),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 13.5,
              height: 1.2,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 11.5,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckPlansButton extends StatelessWidget {
  const _CheckPlansButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 58),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: const LinearGradient(colors: _premiumGradientColors),
            boxShadow: [
              BoxShadow(
                color: AppColors.secondary.withValues(alpha: .38),
                blurRadius: 26,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onTap,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 18, vertical: 15),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(
                      'Check plans',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 19,
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown while the entitlement is active — and, when [justActivated],
/// plays the welcome moment (Part 27): the premium ring appearing around
/// the identity with restrained copy. No confetti.
class _PremiumActiveView extends StatelessWidget {
  const _PremiumActiveView({
    required this.entitlements,
    required this.justActivated,
    required this.onManageSubscription,
  });

  final SubscriptionEntitlements entitlements;
  final bool justActivated;
  final VoidCallback onManageSubscription;

  @override
  Widget build(BuildContext context) {
    final periodEnd = entitlements.currentPeriodEnd;
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: justActivated ? 0.6 : 1.0, end: 1.0),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutBack,
                builder: (context, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: const PremiumAvatarFrame(
                  child: CircleAvatar(
                    radius: 44,
                    backgroundColor: Color(0xFF281133),
                    child: Icon(
                      Icons.graphic_eq_rounded,
                      color: Color(0xFFD3A5FF),
                      size: 38,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                justActivated
                    ? 'Welcome to YO Voice Premium'
                    : 'You have YO Voice Premium',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your voice just got more room to grow.',
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: palette.border),
                ),
                child: Text(
                  '${entitlements.plan.label} plan'
                  '${periodEnd == null ? '' : ' · renews/ends '
                            '${periodEnd.day}.${periodEnd.month}.${periodEnd.year}'}'
                  '${entitlements.inGracePeriod ? ' · payment issue — check your billing' : ''}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: palette.textSecondary, fontSize: 13),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: onManageSubscription,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: colors.onPrimary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 14,
                  ),
                ),
                child: const Text(
                  'Manage subscription',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
