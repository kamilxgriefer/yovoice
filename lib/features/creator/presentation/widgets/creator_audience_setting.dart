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

bool creatorAudienceCanConfirmAge(
  UserProfile profile,
  SubscriptionEntitlements entitlements,
) =>
    profile.accountType == AccountType.creator &&
    !profile.creatorAgeVerified &&
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
    creatorAudienceCanEnable(profile, entitlements) ||
    creatorAudienceCanConfirmAge(profile, entitlements);

class CreatorAudienceSetting extends StatefulWidget {
  const CreatorAudienceSetting({
    required this.ownerEnabled,
    required this.publicVisible,
    required this.canEnable,
    required this.service,
    this.ageVerified = true,
    this.canConfirmAge = false,
    this.birthDateSelector,
    this.onSaved,
    super.key,
  });

  final bool ownerEnabled;
  final bool publicVisible;
  final bool canEnable;
  final bool ageVerified;
  final bool canConfirmAge;
  final Future<DateTime?> Function(BuildContext context)? birthDateSelector;
  final CreatorAudienceService service;
  final ValueChanged<CreatorAudienceUpdate>? onSaved;

  @override
  State<CreatorAudienceSetting> createState() => _CreatorAudienceSettingState();
}

class _CreatorAudienceSettingState extends State<CreatorAudienceSetting> {
  late bool _enabled = widget.ownerEnabled;
  late bool _visible = widget.publicVisible;
  bool _busy = false;
  late bool _ageVerified = widget.ageVerified;
  CreatorAudienceFailure? _failure;
  bool _saved = false;
  bool _ageConfirmationSaved = false;
  String? _pendingRequestId;
  bool? _pendingEnabled;
  String? _pendingAgeRequestId;
  DateTime? _pendingBirthDate;

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
    if (oldWidget.ageVerified != widget.ageVerified) {
      _ageVerified = widget.ageVerified;
      if (_ageVerified) {
        _pendingAgeRequestId = null;
        _pendingBirthDate = null;
      }
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
        _ageConfirmationSaved = false;
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
        _ageConfirmationSaved = false;
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

  Future<void> _confirmAdultEligibility() async {
    if (_busy || _ageVerified || !widget.canConfirmAge) return;
    final now = DateTime.now();
    final latestAdultDate = DateTime(now.year - 18, now.month, now.day);
    final pendingBirthDate = _pendingBirthDate;
    final injectedSelector = widget.birthDateSelector;
    DateTime? birthDate = pendingBirthDate;
    if (birthDate == null) {
      if (injectedSelector != null) {
        birthDate = await injectedSelector(context);
      } else {
        final helpText = AppLocalizations.of(context).text(
          'Confirm that you are 18+',
          'Potwierdź, że masz co najmniej 18 lat',
        );
        birthDate = await showDatePicker(
          context: context,
          initialDate: DateTime(now.year - 25, now.month, now.day),
          firstDate: DateTime(now.year - 120, now.month, now.day),
          lastDate: latestAdultDate,
          helpText: helpText,
        );
      }
    }
    if (birthDate == null || !mounted) return;
    late final String requestId;
    try {
      requestId = _pendingAgeRequestId ?? widget.service.newRequestId();
    } on CreatorAudienceException catch (error) {
      setState(() {
        _failure = error.failure;
        _saved = false;
        _ageConfirmationSaved = false;
      });
      return;
    }
    _pendingAgeRequestId = requestId;
    _pendingBirthDate = birthDate;
    setState(() {
      _busy = true;
      _failure = null;
      _saved = false;
      _ageConfirmationSaved = false;
    });
    try {
      final result = await widget.service.confirmAdultEligibility(
        birthDate: birthDate,
        requestId: requestId,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _ageVerified = result.verified;
        _ageConfirmationSaved = result.verified;
        _pendingAgeRequestId = null;
        _pendingBirthDate = null;
      });
    } on CreatorAudienceException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failure = error.failure;
        _ageConfirmationSaved = false;
        if (error.failure != CreatorAudienceFailure.unavailable &&
            error.failure != CreatorAudienceFailure.invalidResponse) {
          _pendingAgeRequestId = null;
          _pendingBirthDate = null;
        }
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
                              'YO Voice privately checks your Creator Premium, age confirmation and opt-in when you turn this on.',
                              'Po włączeniu YO Voice prywatnie sprawdzi Creator Premium, potwierdzenie wieku i Twoją zgodę.',
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
                  onChanged:
                      widget.canEnable ||
                          (_ageVerified && widget.canConfirmAge) ||
                          _enabled
                      ? _setEnabled
                      : null,
                ),
            ],
          ),
          if (!_ageVerified && widget.canConfirmAge) ...[
            const SizedBox(height: 14),
            Container(
              key: const ValueKey('creator-age-confirmation'),
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: const Color(0xFF21162B),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.verified_user_outlined,
                    color: Color(0xFFC863FF),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      copy.text(
                        'Confirm you are 18+ to enable Follow. Your birth date is used only for this age check and is not saved.',
                        'Potwierdź, że masz co najmniej 18 lat, aby włączyć Obserwuj. Data urodzenia służy wyłącznie do sprawdzenia wieku i nie jest zapisywana.',
                      ),
                      style: const TextStyle(
                        color: Color(0xFFD9CFDF),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    key: const ValueKey('confirm-creator-age-button'),
                    onPressed: _busy ? null : _confirmAdultEligibility,
                    child: Text(copy.text('Confirm age', 'Potwierdź wiek')),
                  ),
                ],
              ),
            ),
          ],
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
          'Audience sharing is unavailable. Check Creator Premium and age confirmation, then try again.',
          'Udostępnianie społeczności jest niedostępne. Sprawdź Creator Premium i potwierdzenie wieku, a potem spróbuj ponownie.',
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
    if (_ageConfirmationSaved) {
      return copy.text(
        'Age confirmed. You can now enable Follow.',
        'Wiek potwierdzony. Możesz teraz włączyć Obserwuj.',
      );
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
