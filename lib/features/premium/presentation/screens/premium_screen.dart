import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:yovoice/features/premium/data/models/subscription_entitlements.dart';
import 'package:yovoice/features/premium/data/premium_plans.dart';
import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/shared/widgets/profile/premium_avatar_frame.dart';

const _background = Color(0xFF0D0618);
const _surface = Color(0xFF191329);
const _border = Color(0xFF3A3151);
const _muted = Color(0xFFB4ADC8);
const _primary = Color(0xFF7B2FF7);

/// The YO Voice Premium page: benefits, plan cards, purchase entry points
/// and — because it watches the entitlement stream — the success state.
///
/// Purchase flow honesty: tapping a plan calls the `verifyPurchase`
/// backend, which (until the store adapters are configured) declines with
/// a clear message. Nothing is unlocked optimistically; the screen flips
/// to the success state only when the TRUSTED entitlements document turns
/// premium — which also makes this the natural landing after an admin
/// grant or a future real purchase, with zero extra wiring.
class PremiumScreen extends StatefulWidget {
  const PremiumScreen({this.entitlementService, super.key});

  final EntitlementService? entitlementService;

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  late final EntitlementService _entitlements =
      widget.entitlementService ?? EntitlementService();

  bool _busy = false;
  bool _wasPremiumOnOpen = false;
  bool _checkedInitial = false;

  Future<void> _attemptPurchase(PremiumProduct product) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await FirebaseFunctions.instanceFor(
        region: 'europe-west1',
      ).httpsCallable('verifyPurchase').call<void>({
        'platform': Theme.of(context).platform.name,
        'productId': product.storeProductId,
      });
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.code == 'failed-precondition'
                ? (error.message ?? 'Purchases are not enabled yet.')
                : 'Something went wrong. Please try again.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Something went wrong. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openUrl(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: Colors.white,
        title: const Text('YO Voice Premium'),
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
            );
          }

          return _PaywallView(
            busy: _busy,
            onSelect: _attemptPurchase,
            onRestore: () => _attemptPurchase(PremiumPlans.monthly),
            onOpenUrl: _openUrl,
          );
        },
      ),
    );
  }
}

class _PaywallView extends StatelessWidget {
  const _PaywallView({
    required this.busy,
    required this.onSelect,
    required this.onRestore,
    required this.onOpenUrl,
  });

  final bool busy;
  final ValueChanged<PremiumProduct> onSelect;
  final VoidCallback onRestore;
  final ValueChanged<String> onOpenUrl;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 40),
          children: [
            // Identity preview: the actual premium ring, not a mockup.
            Center(
              child: PremiumAvatarFrame(
                child: CircleAvatar(
                  radius: 40,
                  backgroundColor: const Color(0xFF281133),
                  child: Image.asset(
                    'assets/images/logo.png',
                    width: 44,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.graphic_eq_rounded,
                      color: Color(0xFFD3A5FF),
                      size: 34,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Unlock more of your voice',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 27,
                fontWeight: FontWeight.w900,
                letterSpacing: -.5,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Premium adds identity and creation on top of everything '
              'free members already have.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 26),
            for (final (title, description) in PremiumPlans.benefits)
              _BenefitRow(title: title, description: description),
            const SizedBox(height: 26),
            for (final product in PremiumPlans.all) ...[
              _PlanCard(product: product, busy: busy, onSelect: onSelect),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: busy ? null : onRestore,
                child: const Text(
                  'Restore purchases',
                  style: TextStyle(color: Color(0xFFD3A5FF)),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () => onOpenUrl('https://yovoice.app/terms'),
                  child: const Text(
                    'Terms',
                    style: TextStyle(color: _muted, fontSize: 12),
                  ),
                ),
                const Text('·', style: TextStyle(color: _muted)),
                TextButton(
                  onPressed: () => onOpenUrl('https://yovoice.app/privacy'),
                  child: const Text(
                    'Privacy',
                    style: TextStyle(color: _muted, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _primary.withValues(alpha: .16),
              border: Border.all(color: _primary.withValues(alpha: .4)),
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 18,
              color: Color(0xFFD3A5FF),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.product,
    required this.busy,
    required this.onSelect,
  });

  final PremiumProduct product;
  final bool busy;
  final ValueChanged<PremiumProduct> onSelect;

  @override
  Widget build(BuildContext context) {
    final highlight = product.highlight;

    return Material(
      color: _surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: busy ? null : () => onSelect(product),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: highlight ? const Color(0xFFC026FF) : _border,
              width: highlight ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          product.plan.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        if (highlight) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFFC026FF,
                              ).withValues(alpha: .18),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: const Text(
                              'Best value',
                              style: TextStyle(
                                color: Color(0xFFE9B8FF),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (product.equivalentMonthlyPrice != null ||
                        product.savingsLabel != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          [
                            product.equivalentMonthlyPrice,
                            product.savingsLabel,
                          ].whereType<String>().join(' · '),
                          style: const TextStyle(color: _muted, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    product.displayPrice,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                    ),
                  ),
                  Text(
                    product.billingPeriodLabel,
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ],
              ),
            ],
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
  });

  final SubscriptionEntitlements entitlements;
  final bool justActivated;

  @override
  Widget build(BuildContext context) {
    final periodEnd = entitlements.currentPeriodEnd;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(28),
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
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your voice just got more room to grow.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _muted, fontSize: 14),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _border),
                ),
                child: Text(
                  '${entitlements.plan.label} plan'
                  '${periodEnd == null ? '' : ' · renews/ends '
                            '${periodEnd.day}.${periodEnd.month}.${periodEnd.year}'}'
                  '${entitlements.inGracePeriod ? ' · payment issue — check your billing' : ''}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _muted, fontSize: 13),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: _primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 14,
                  ),
                ),
                child: const Text(
                  'Explore Premium',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
