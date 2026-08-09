import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/features/premium/data/models/subscription_entitlements.dart';
import 'package:yovoice/features/premium/data/premium_plans.dart';
import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/features/premium/presentation/widgets/premium_badge_pill.dart';

/// The plans & purchase screen — where the "Check plans" CTA lands.
///
/// Purchase flow honesty (unchanged from the original combined screen):
/// choosing a plan calls the `verifyPurchase` backend, which — until the
/// store adapters are configured — declines with a clear message. Nothing
/// is unlocked optimistically. The screen watches the TRUSTED entitlement
/// stream; if it flips premium while open (a real purchase or an admin
/// grant), it pops back to [PremiumScreen], which plays the welcome state.
class PremiumPlansScreen extends StatefulWidget {
  const PremiumPlansScreen({this.entitlementService, super.key});

  final EntitlementService? entitlementService;

  @override
  State<PremiumPlansScreen> createState() => _PremiumPlansScreenState();
}

class _PremiumPlansScreenState extends State<PremiumPlansScreen> {
  late final EntitlementService _entitlements =
      widget.entitlementService ?? EntitlementService();

  PremiumPlan _selected = PremiumPlan.yearly;
  bool _busy = false;
  bool _wasPremiumOnOpen = false;
  bool _checkedInitial = false;
  bool _popScheduled = false;

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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<SubscriptionEntitlements>(
        stream: _entitlements.watchCurrentEntitlements(),
        builder: (context, snapshot) {
          final entitlements = snapshot.data ?? SubscriptionEntitlements.free;

          if (!_checkedInitial && snapshot.hasData) {
            _wasPremiumOnOpen = entitlements.isPremium;
            _checkedInitial = true;
          }

          // A purchase (or grant) landed while this screen was open —
          // return to PremiumScreen, which now shows the welcome state.
          if (_checkedInitial &&
              !_wasPremiumOnOpen &&
              entitlements.isPremium &&
              !_popScheduled) {
            _popScheduled = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            });
          }

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 40),
                children: [
                  const Center(child: PremiumBadgePill()),
                  const SizedBox(height: 16),
                  const Text(
                    'Choose your plan',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Unlock the full YO Voice experience',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14.5,
                    ),
                  ),
                  const SizedBox(height: 22),
                  _PlanToggle(
                    selected: _selected,
                    onChanged: (plan) => setState(() => _selected = plan),
                  ),
                  const SizedBox(height: 20),
                  _PlanCards(
                    selected: _selected,
                    busy: _busy,
                    onSelect: (plan) => setState(() => _selected = plan),
                    onChoose: _attemptPurchase,
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Everything Premium includes:',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const _EverythingIncluded(),
                  const SizedBox(height: 20),
                  const _TrustFooter(),
                  const SizedBox(height: 10),
                  Center(
                    child: TextButton(
                      onPressed: _busy
                          ? null
                          : () => _attemptPurchase(PremiumPlans.monthly),
                      child: const Text(
                        'Restore purchases',
                        style: TextStyle(color: Color(0xFFD3A5FF)),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () => _openUrl('https://yovoice.app/terms'),
                        child: const Text(
                          'Terms',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const Text(
                        '·',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      TextButton(
                        onPressed: () =>
                            _openUrl('https://yovoice.app/privacy'),
                        child: const Text(
                          'Privacy',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Monthly | Yearly segmented control with the "-25%" chip on Yearly.
class _PlanToggle extends StatelessWidget {
  const _PlanToggle({required this.selected, required this.onChanged});

  final PremiumPlan selected;
  final ValueChanged<PremiumPlan> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: .07)),
      ),
      child: Row(
        children: [
          _segment(
            label: 'Monthly',
            plan: PremiumPlan.monthly,
          ),
          _segment(
            label: 'Yearly',
            plan: PremiumPlan.yearly,
            chip: '-25%',
          ),
        ],
      ),
    );
  }

  Widget _segment({
    required String label,
    required PremiumPlan plan,
    String? chip,
  }) {
    final active = selected == plan;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(plan),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: active ? AppColors.surfaceLight : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active
                  ? Colors.white.withValues(alpha: .12)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: active ? Colors.white : AppColors.textSecondary,
                  fontSize: 13.5,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
              if (chip != null) ...[
                const SizedBox(width: 7),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2.5,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.secondary],
                    ),
                  ),
                  child: const Text(
                    '-25%',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The Monthly + Yearly cards side by side; the selected plan carries the
/// glow treatment and the gradient button. "Best value" stays on Yearly
/// regardless of selection — it's a fact about the plan, not a UI state.
class _PlanCards extends StatelessWidget {
  const _PlanCards({
    required this.selected,
    required this.busy,
    required this.onSelect,
    required this.onChoose,
  });

  final PremiumPlan selected;
  final bool busy;
  final ValueChanged<PremiumPlan> onSelect;
  final ValueChanged<PremiumProduct> onChoose;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _PlanCard(
              product: PremiumPlans.monthly,
              selected: selected == PremiumPlan.monthly,
              checkColor: AppColors.accent,
              busy: busy,
              onSelect: onSelect,
              onChoose: onChoose,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _PlanCard(
              product: PremiumPlans.yearly,
              selected: selected == PremiumPlan.yearly,
              checkColor: const Color(0xFFE879F9),
              busy: busy,
              onSelect: onSelect,
              onChoose: onChoose,
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
    required this.selected,
    required this.checkColor,
    required this.busy,
    required this.onSelect,
    required this.onChoose,
  });

  final PremiumProduct product;
  final bool selected;
  final Color checkColor;
  final bool busy;
  final ValueChanged<PremiumPlan> onSelect;
  final ValueChanged<PremiumProduct> onChoose;

  @override
  Widget build(BuildContext context) {
    final card = GestureDetector(
      onTap: () => onSelect(product.plan),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: selected
              ? const Color(0xFF1E1233)
              : AppColors.surface.withValues(alpha: .55),
          border: Border.all(
            color: selected
                ? AppColors.secondary.withValues(alpha: .75)
                : AppColors.border,
            width: selected ? 1.4 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.secondary.withValues(alpha: .26),
                    blurRadius: 30,
                    offset: const Offset(0, 4),
                  ),
                ]
              : const [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              product.plan.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              product.displayPrice,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: -.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              product.billingPeriodLabel,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            if (product.equivalentMonthlyPrice != null) ...[
              const SizedBox(height: 4),
              Text(
                product.equivalentMonthlyPrice!,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
            if (product.savingsLabel != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4.5,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.secondary],
                  ),
                ),
                child: Text(
                  product.savingsLabel!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            for (final item in PremiumPlans.planChecklist)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  children: [
                    Icon(Icons.check_rounded, size: 14, color: checkColor),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        item,
                        style: const TextStyle(
                          color: Color(0xFFDDD8E8),
                          fontSize: 12.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const Spacer(),
            const SizedBox(height: 8),
            _chooseButton(),
          ],
        ),
      ),
    );

    // Reserve headroom so the "Best value" pill can straddle the border
    // while both cards stay top-aligned.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(padding: const EdgeInsets.only(top: 13), child: card),
        if (product.highlight)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.secondary],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.secondary.withValues(alpha: .45),
                      blurRadius: 14,
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.workspace_premium_rounded,
                      size: 12,
                      color: Colors.white,
                    ),
                    SizedBox(width: 5),
                    Text(
                      'Best value',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _chooseButton() {
    final label = 'Choose\n${product.plan.label.toLowerCase()}';

    if (selected) {
      return SizedBox(
        width: double.infinity,
        height: 58,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.secondary],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.secondary.withValues(alpha: .35),
                blurRadius: 18,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: busy ? null : () => onChoose(product),
              child: Center(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.25,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 58,
      child: Material(
        color: AppColors.surfaceLight.withValues(alpha: .65),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: busy ? null : () => onChoose(product),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: .10)),
            ),
            child: Center(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.25,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EverythingIncluded extends StatelessWidget {
  const _EverythingIncluded();

  static const _icons = [
    Icons.person_outline_rounded,
    Icons.workspace_premium_outlined,
    Icons.graphic_eq_rounded,
    Icons.auto_awesome_outlined,
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: AppColors.surface.withValues(alpha: .45),
        border: Border.all(color: Colors.white.withValues(alpha: .07)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < PremiumPlans.everythingIncluded.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(_icons[i], size: 19, color: const Color(0xFFD3A5FF)),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Text(
                      PremiumPlans.everythingIncluded[i],
                      style: const TextStyle(
                        color: Color(0xFFEFEAF7),
                        fontSize: 13.3,
                        fontWeight: FontWeight.w600,
                      ),
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

class _TrustFooter extends StatelessWidget {
  const _TrustFooter();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.verified_user_outlined,
          size: 13,
          color: AppColors.textSecondary,
        ),
        SizedBox(width: 5),
        Text(
          'Secure checkout',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        SizedBox(width: 16),
        Icon(Icons.schedule_rounded, size: 13, color: AppColors.textSecondary),
        SizedBox(width: 5),
        Text(
          'Cancel anytime',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ],
    );
  }
}
