import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/creator/data/services/creator_audience_service.dart';
import 'package:yovoice/features/premium/data/models/subscription_entitlements.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';

/// Paid Creator authority from the server-written entitlement document.
/// Moderator preview and the profile's decorative Premium identity are not
/// purchase proof for this age-gated public surface.
bool creatorAudienceCanEnable(
  UserProfile profile,
  SubscriptionEntitlements entitlements,
) =>
    profile.accountType == AccountType.creator &&
    profile.creatorAgeVerified &&
    entitlements.isPremium &&
    entitlements.premiumIdentityEnabled &&
    entitlements.creatorEnabled;

/// Shows the control to an eligible paid Creator, or to anyone who still has
/// an enabled owner opt-in and therefore needs a durable way to turn it off
/// after losing authority.
bool creatorAudienceSettingIsAvailable(
  UserProfile profile,
  SubscriptionEntitlements entitlements,
) =>
    profile.creatorAudienceEnabled ||
    creatorAudienceCanEnable(profile, entitlements);

class CreatorAudienceSetting extends StatefulWidget {
  const CreatorAudienceSetting({
    required this.ownerEnabled,
    required this.publicVisible,
    required this.canEnable,
    required this.service,
    this.onSaved,
    super.key,
  });

  final bool ownerEnabled;
  final bool publicVisible;
  final bool canEnable;
  final CreatorAudienceService service;
  final ValueChanged<CreatorAudienceUpdate>? onSaved;

  @override
  State<CreatorAudienceSetting> createState() => _CreatorAudienceSettingState();
}

class _CreatorAudienceSettingState extends State<CreatorAudienceSetting> {
  late bool _enabled = widget.ownerEnabled;
  late bool _visible = widget.publicVisible;
  bool _busy = false;
  CreatorAudienceFailure? _failure;
  bool _saved = false;
  String? _pendingRequestId;
  bool? _pendingEnabled;

  @override
  void didUpdateWidget(CreatorAudienceSetting oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ownerEnabled != widget.ownerEnabled) {
      _enabled = widget.ownerEnabled;
      if (_pendingEnabled == widget.ownerEnabled) {
        _pendingRequestId = null;
        _pendingEnabled = null;
      }
    }
    if (oldWidget.publicVisible != widget.publicVisible) {
      _visible = widget.publicVisible;
    }
  }

  Future<void> _setEnabled(bool enabled) async {
    if (_busy) return;
    final reusePending = _pendingEnabled == enabled;
    late final String requestId;
    try {
      requestId = reusePending && _pendingRequestId != null
          ? _pendingRequestId!
          : widget.service.newRequestId();
    } on CreatorAudienceException catch (error) {
      setState(() {
        _failure = error.failure;
        _saved = false;
      });
      return;
    }
    _pendingEnabled = enabled;
    _pendingRequestId = requestId;
    setState(() {
      _busy = true;
      _failure = null;
      _saved = false;
    });
    try {
      final result = await widget.service.setEnabled(
        enabled: enabled,
        requestId: requestId,
      );
      if (!mounted) return;
      setState(() {
        _enabled = result.enabled;
        _visible = result.visible;
        _busy = false;
        _saved = true;
        _pendingRequestId = null;
        _pendingEnabled = null;
      });
      widget.onSaved?.call(result);
    } on CreatorAudienceException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failure = error.failure;
        _saved = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final feedback = _feedback(copy);
    return Container(
      key: const ValueKey('creator-audience-setting'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF17101F),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF3C2C45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(
                Icons.people_alt_rounded,
                color: Color(0xFFC863FF),
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      copy.text(
                        'Public creator audience',
                        'Publiczna społeczność twórcy',
                      ),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _visible
                          ? copy.text(
                              'Followers and following are visible on your creator profile.',
                              'Obserwujący i obserwowani są widoczni na Twoim profilu twórcy.',
                            )
                          : copy.text(
                              'YO Voice privately checks your Creator Premium and account verification when you turn this on.',
                              'Po włączeniu YO Voice prywatnie sprawdzi Creator Premium i weryfikację konta.',
                            ),
                      style: const TextStyle(
                        color: Color(0xFFA99DB3),
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (_busy)
                const SizedBox.square(
                  key: ValueKey('creator-audience-saving'),
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                )
              else
                Switch(
                  key: const ValueKey('creator-audience-switch'),
                  value: _enabled,
                  onChanged: widget.canEnable || _enabled ? _setEnabled : null,
                ),
            ],
          ),
          if (feedback != null) ...[
            const SizedBox(height: 10),
            Semantics(
              liveRegion: true,
              child: Text(
                feedback,
                key: const ValueKey('creator-audience-feedback'),
                style: TextStyle(
                  color: _failure == null
                      ? const Color(0xFF9BE6BD)
                      : const Color(0xFFFFB4AB),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String? _feedback(AppLocalizations copy) {
    final failure = _failure;
    if (failure != null) {
      return switch (failure) {
        CreatorAudienceFailure.unauthenticated => copy.text(
          'Sign in again before changing this setting.',
          'Zaloguj się ponownie przed zmianą tego ustawienia.',
        ),
        CreatorAudienceFailure.eligibility => copy.text(
          'Audience sharing is unavailable. Check Creator Premium and account verification, then try again.',
          'Udostępnianie społeczności jest niedostępne. Sprawdź Creator Premium i weryfikację konta, a potem spróbuj ponownie.',
        ),
        CreatorAudienceFailure.inactiveAccount => copy.text(
          'This setting is unavailable while the account is inactive.',
          'To ustawienie jest niedostępne, gdy konto jest nieaktywne.',
        ),
        CreatorAudienceFailure.conflictingRequest ||
        CreatorAudienceFailure.staleRequest => copy.text(
          'Your profile changed during this request. Review the current setting and try again.',
          'Twój profil zmienił się podczas tej operacji. Sprawdź bieżące ustawienie i spróbuj ponownie.',
        ),
        CreatorAudienceFailure.invalidRequest ||
        CreatorAudienceFailure.invalidResponse ||
        CreatorAudienceFailure.unavailable => copy.text(
          'The setting could not be saved. Check your connection and try again.',
          'Nie udało się zapisać ustawienia. Sprawdź połączenie i spróbuj ponownie.',
        ),
      };
    }
    if (!_saved) return null;
    return _visible
        ? copy.text(
            'Your creator audience is now visible.',
            'Twoja społeczność twórcy jest teraz widoczna.',
          )
        : copy.text(
            'Your creator audience is now private.',
            'Twoja społeczność twórcy jest teraz prywatna.',
          );
  }
}
