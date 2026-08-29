import 'package:flutter/material.dart';

import 'package:yovoice/shared/identity/public_identity.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';
import 'package:yovoice/shared/widgets/identity/official_role_badge.dart';
import 'package:yovoice/shared/widgets/identity/vip_badge.dart';

/// The authoritative identity badges for one user, resolved and rendered.
///
/// Give it a uid and it shows the official role badge — ALWAYS, an
/// ordinary account included — followed by VIP when the entitlement is
/// active, laid out in a [Wrap] so a narrow surface wraps instead of
/// overflowing. Resolution goes through [PublicIdentityRepository]
/// (batched, cached, server-authoritative); the widget renders the USER
/// fallback until the real answer lands, and re-resolves when the
/// repository's revision bumps after a role or VIP change.
///
/// Never construct badges from fields embedded in a message or any other
/// client-written data — the sender's client wrote those.
///
/// [achievementStyle] is the RESERVED cosmetic slot for the Achievement
/// Rank milestone: an optional rank chip rendered strictly AFTER the
/// official badges, visually subordinate, and never able to replace or
/// restyle them. Nothing passes one yet — there is no selection flow
/// until server-validated achievement data exists.
class UserIdentityBadges extends StatefulWidget {
  const UserIdentityBadges({
    required this.uid,
    this.variant = IdentityBadgeVariant.compact,
    this.achievementStyle,
    this.repository,
    super.key,
  });

  final String uid;
  final IdentityBadgeVariant variant;
  final AchievementStyle? achievementStyle;

  /// Test seam; the app always uses [PublicIdentityRepository.instance].
  final PublicIdentityRepository? repository;

  @override
  State<UserIdentityBadges> createState() => _UserIdentityBadgesState();
}

class _UserIdentityBadgesState extends State<UserIdentityBadges> {
  PublicIdentity _identity = PublicIdentity.fallback;
  late PublicIdentityRepository _repository;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? PublicIdentityRepository.instance;
    _repository.revision.addListener(_resolve);
    _resolve();
  }

  @override
  void didUpdateWidget(UserIdentityBadges oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextRepository =
        widget.repository ?? PublicIdentityRepository.instance;
    final repositoryChanged = !identical(nextRepository, _repository);
    if (repositoryChanged) {
      _repository.revision.removeListener(_resolve);
      _repository = nextRepository;
      _repository.revision.addListener(_resolve);
    }
    if (oldWidget.uid != widget.uid || repositoryChanged) {
      _identity = PublicIdentity.fallback;
      _resolve();
    }
  }

  @override
  void dispose() {
    _repository.revision.removeListener(_resolve);
    super.dispose();
  }

  void _resolve() {
    if (!mounted) return;
    final cached = _repository.peek(widget.uid);
    if (cached != null) {
      if (cached != _identity) setState(() => _identity = cached);
      return;
    }
    final requestedUid = widget.uid;
    _repository.resolve(requestedUid).then((identity) {
      if (!mounted || requestedUid != widget.uid) return;
      if (identity != _identity) setState(() => _identity = identity);
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.achievementStyle;
    return Wrap(
      spacing: widget.variant == IdentityBadgeVariant.icon ? 3 : 5,
      runSpacing: 3,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OfficialRoleBadge(role: _identity.role, variant: widget.variant),
        if (_identity.isVip) VipBadge(variant: widget.variant),
        // Cosmetic rank AFTER — and never instead of — the official
        // badges. Plain text, no pill chrome, so it cannot pass for one.
        if (style?.rankLabel != null &&
            widget.variant != IdentityBadgeVariant.icon)
          Text(
            style!.rankLabel!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: style.rankColor ?? _identity.role.color,
              fontSize: widget.variant == IdentityBadgeVariant.compact
                  ? 9.5
                  : 11,
              fontWeight: FontWeight.w600,
              fontStyle: FontStyle.italic,
            ),
          ),
      ],
    );
  }
}
