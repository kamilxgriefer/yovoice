import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/premium/data/models/subscription_entitlements.dart';
import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/features/premium/presentation/widgets/premium_upsell_sheet.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/image_crop.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/profile/presentation/screens/image_crop_screen.dart';
import 'package:yovoice/shared/widgets/profile/profile_banner.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';
import 'package:yovoice/shared/widgets/inputs/yo_keyboard_done_bar.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    required this.profile,
    this.service,
    this.entitlements,
    this.clock,
    super.key,
  });

  final UserProfile profile;

  /// Injectable so the end-to-end save test (test/profile_save_e2e_test.dart)
  /// can drive THIS screen's real pick→validate→upload→persist pipeline
  /// against mock Firebase backends. Production callers pass nothing.
  final ProfileService? service;

  /// Injectable for the premium-gating tests.
  final EntitlementService? entitlements;

  /// Injectable clock for deterministic cooldown and boundary tests.
  final DateTime Function()? clock;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final ProfileService _service = widget.service ?? ProfileService();
  late final EntitlementService _entitlementService =
      widget.entitlements ?? EntitlementService();
  late final Stream<SubscriptionEntitlements> _entitlements =
      _watchEntitlements();
  final _formKey = GlobalKey<FormState>();

  Stream<SubscriptionEntitlements> _watchEntitlements() {
    try {
      return _entitlementService.watchCurrentEntitlements();
    } catch (_) {
      // Auth can disappear while this route is mounted (and preview
      // harnesses intentionally have no session). Access always fails closed;
      // a missing session must not crash the whole form.
      return Stream<SubscriptionEntitlements>.value(
        SubscriptionEntitlements.free,
      );
    }
  }

  late final TextEditingController _displayName;
  late final TextEditingController _username;
  late final TextEditingController _statusMessage;
  late final TextEditingController _bio;
  late final TextEditingController _country;
  late final TextEditingController _nativeLanguage;
  late final TextEditingController _spokenLanguages;
  late final TextEditingController _learningLanguages;
  late final TextEditingController _website;

  bool _saving = false;
  bool _pickingAvatar = false;
  bool _pickingBanner = false;
  late AccountType _accountType;
  late String _savedDisplayName;
  DateTime? _nextDisplayNameChangeAt;
  bool _displayNameSyncPending = false;
  Timer? _displayNameCooldownTimer;

  AppLocalizations get _copy => AppLocalizations.of(context);

  DateTime get _now => (widget.clock ?? DateTime.now)();

  bool get _canChangeDisplayName {
    final next = _nextDisplayNameChangeAt;
    return next == null || !_now.isBefore(next);
  }

  /// Chosen but not yet uploaded. Images commit on Save together with the
  /// text fields, so backing out leaves the remote profile untouched and
  /// never orphans a Storage object.
  PickedProfileImage? _pendingAvatar;
  PickedProfileImage? _pendingBanner;

  bool get _hasPendingImages =>
      _pendingAvatar != null || _pendingBanner != null;

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    _displayName = TextEditingController(text: profile.displayName);
    // Preserve the exact canonical-store value for change detection. Legacy
    // records may contain surrounding whitespace; sending the trimmed value
    // is then a real server-side normalization and must start the cooldown.
    _savedDisplayName = profile.displayName;
    _nextDisplayNameChangeAt = profile.nextDisplayNameChangeAt;
    _username = TextEditingController(text: profile.username);
    _statusMessage = TextEditingController(text: profile.statusMessage);
    _bio = TextEditingController(text: profile.bio);
    _country = TextEditingController(text: profile.country);
    _nativeLanguage = TextEditingController(text: profile.nativeLanguage);
    _spokenLanguages = TextEditingController(
      text: profile.spokenLanguages.join(', '),
    );
    _learningLanguages = TextEditingController(
      text: profile.learningLanguages.join(', '),
    );
    _website = TextEditingController(text: profile.website);
    _accountType = profile.accountType;
    _scheduleDisplayNameCooldownRefresh();
  }

  @override
  void dispose() {
    _displayNameCooldownTimer?.cancel();
    _displayName.dispose();
    _username.dispose();
    _statusMessage.dispose();
    _bio.dispose();
    _country.dispose();
    _nativeLanguage.dispose();
    _spokenLanguages.dispose();
    _learningLanguages.dispose();
    _website.dispose();
    super.dispose();
  }

  List<String> _split(TextEditingController controller) {
    return controller.text
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) {
      // A silent return here looked like a successful no-op save — the
      // user pressed Save, nothing happened, they left assuming it
      // worked. Validation failure must be loud.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _copy.text(
              'Please fix the highlighted fields before saving.',
              'Popraw zaznaczone pola przed zapisaniem.',
            ),
          ),
        ),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    var displayNameSavedDuringAttempt = false;
    setState(() => _saving = true);
    try {
      // Re-check immediately before the write. The member may have selected
      // Creator while Premium was active and then lost the entitlement before
      // pressing Save; doing this before image uploads avoids side effects for
      // a profile mutation Firestore will correctly reject anyway.
      final activatingCreator =
          _accountType == AccountType.creator &&
          widget.profile.accountType != AccountType.creator;
      if (activatingCreator) {
        SubscriptionEntitlements entitlements;
        try {
          entitlements = await _entitlementService.currentEntitlements();
        } catch (_) {
          entitlements = SubscriptionEntitlements.free;
        }
        if (!entitlements.canUseCreator) {
          if (mounted) {
            await showPremiumUpsellSheet(
              context,
              upsellContext: PremiumUpsellContext.creator,
            );
          }
          return;
        }
      }

      final requestedDisplayName = _displayName.text.trim();
      final displayNameChanged = requestedDisplayName != _savedDisplayName;
      if (displayNameChanged || _displayNameSyncPending) {
        try {
          final result = await _service.updateDisplayName(requestedDisplayName);
          displayNameSavedDuringAttempt = result.changed;
          _savedDisplayName = result.displayName;
          _displayName.text = result.displayName;
          _nextDisplayNameChangeAt = result.nextDisplayNameChangeAt;
          _scheduleDisplayNameCooldownRefresh();
          _displayNameSyncPending = false;
        } on DisplayNameChangeException catch (error) {
          if (error.failure == DisplayNameChangeFailure.cooldown) {
            _nextDisplayNameChangeAt = error.nextDisplayNameChangeAt;
            // The attempted value was rejected. Restore the canonical value
            // before locking the field so the UI never presents an unsaved
            // name as if it were active across YO Voice.
            _displayName.text = _savedDisplayName;
            _displayNameSyncPending = false;
            _scheduleDisplayNameCooldownRefresh();
          } else if (error.failure ==
              DisplayNameChangeFailure.authSyncPending) {
            final canonical = error.canonicalDisplayName;
            if (canonical != null && canonical.trim().isNotEmpty) {
              _savedDisplayName = canonical;
              _displayName.text = canonical;
            }
            _nextDisplayNameChangeAt = error.nextDisplayNameChangeAt;
            _scheduleDisplayNameCooldownRefresh();
            _displayNameSyncPending = true;
            displayNameSavedDuringAttempt = true;
          } else if (error.failure ==
              DisplayNameChangeFailure.authAccountMissingAfterSave) {
            final canonical = error.canonicalDisplayName;
            if (canonical != null && canonical.trim().isNotEmpty) {
              _savedDisplayName = canonical;
              _displayName.text = canonical;
            }
            _nextDisplayNameChangeAt = error.nextDisplayNameChangeAt;
            _scheduleDisplayNameCooldownRefresh();
            _displayNameSyncPending = false;
            displayNameSavedDuringAttempt = true;
          }
          rethrow;
        }
      }

      // Media and the remaining profile fields retain their existing save
      // pipeline. The display-name callable intentionally ran first so a
      // cooldown/verification rejection cannot upload anything. If a later
      // upload fails, the catch below explicitly tells the member that the
      // already-authorized name change did succeed.
      final avatar = _pendingAvatar;
      if (avatar != null) {
        await _service.uploadProfileImage(avatar);
      }
      final banner = _pendingBanner;
      if (banner != null) {
        await _service.uploadProfileImage(banner);
      }

      await _service.updateProfile(
        username: _username.text,
        bio: _bio.text,
        country: _country.text,
        nativeLanguage: _nativeLanguage.text,
        spokenLanguages: _split(_spokenLanguages),
        learningLanguages: _split(_learningLanguages),
        website: _website.text,
        accountType: _accountType,
        statusMessage: _statusMessage.text,
      );
      // Success is only announced AFTER every stage completed: uploads,
      // Firestore pointer flips and the text-field write. The messenger
      // was captured before the pop so the confirmation survives this
      // screen's disposal.
      if (mounted) Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(_copy.text('Profile saved.', 'Profil zapisany.')),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final message = _friendlySaveError(error);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            displayNameSavedDuringAttempt &&
                    error is! DisplayNameChangeException
                ? _copy.text(
                    'Your display name was saved, but other profile changes failed. $message',
                    'Nazwa wyświetlana została zapisana, ale pozostałych zmian nie udało się zapisać. $message',
                  )
                : message,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pick(ProfileImageKind kind) async {
    final avatar = kind == ProfileImageKind.avatar;
    setState(() {
      if (avatar) {
        _pickingAvatar = true;
      } else {
        _pickingBanner = true;
      }
    });

    try {
      final picked = await _service.pickProfileImage(kind);
      // Null means the user dismissed the picker — not an error.
      if (!mounted || picked == null) return;

      // Crop/adjust step: the editor returns the final processed JPEG —
      // what gets stored IS the crop the user composed, not the original
      // plus display-time alignment tricks.
      final decoded = await ImageCrop.decode(picked.bytes);
      if (!mounted) {
        decoded.dispose();
        return;
      }
      final route = MaterialPageRoute<Uint8List>(
        builder: (_) => ImageCropScreen(image: decoded, kind: kind),
      );
      Uint8List? cropped;
      try {
        cropped = await Navigator.of(context).push<Uint8List>(route);
        // Navigator.push completes when pop begins. Web still paints the
        // reverse transition, so retain the native image until its overlay is
        // fully removed. The caller remains the owner even if push/reset fails.
        await route.completed;
      } finally {
        decoded.dispose();
      }
      // Null means the user backed out of the editor — not an error.
      if (!mounted || cropped == null) return;

      final processed = PickedProfileImage(
        kind: kind,
        bytes: cropped,
        format: ProfileImageFormat.jpeg,
      );
      setState(() {
        if (avatar) {
          _pendingAvatar = processed;
        } else {
          _pendingBanner = processed;
        }
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_friendlySaveError(error))));
      }
    } finally {
      if (mounted) {
        setState(() {
          if (avatar) {
            _pickingAvatar = false;
          } else {
            _pickingBanner = false;
          }
        });
      }
    }
  }

  void _clearPending(ProfileImageKind kind) {
    setState(() {
      if (kind == ProfileImageKind.avatar) {
        _pendingAvatar = null;
      } else {
        _pendingBanner = null;
      }
    });
  }

  /// Maps picker/Storage failures onto copy a person can act on. Raw
  /// Firebase messages ("[firebase_storage/unauthorized] ...") never reach
  /// the user.
  String _friendlySaveError(Object error) {
    if (error is ProfileImageException) {
      final megabytes = RegExp(r'(\d+) MB').firstMatch(error.message)?.group(1);
      if (megabytes != null) {
        return _copy.text(
          error.message,
          'Plik graficzny musi mieć mniej niż $megabytes MB.',
        );
      }
      if (error.message.contains('file type')) {
        return _copy.text(
          error.message,
          'Ten format pliku nie jest obsługiwany. Wybierz obraz JPG, PNG lub WebP.',
        );
      }
      if (error.message.contains('too large to process safely')) {
        return _copy.text(
          error.message,
          'Obraz jest zbyt duży, aby bezpiecznie go przetworzyć. Wybierz inny.',
        );
      }
      return _copy.text(
        error.message,
        'Nie udało się przetworzyć obrazu. Wybierz inny.',
      );
    }
    if (error is DisplayNameChangeException) {
      return switch (error.failure) {
        DisplayNameChangeFailure.cooldown => _copy.text(
          error.message,
          'Nazwę wyświetlaną można zmienić dopiero po upływie wskazanego terminu.',
        ),
        DisplayNameChangeFailure.authSyncPending => _copy.text(
          error.message,
          'Nazwa została zapisana. Naciśnij Zapisz ponownie, aby dokończyć synchronizację konta.',
        ),
        DisplayNameChangeFailure.authAccountMissingAfterSave => _copy.text(
          error.message,
          'Nazwa została zapisana, ale konto wymaga ponownego zalogowania.',
        ),
        DisplayNameChangeFailure.emailVerificationRequired => _copy.text(
          error.message,
          'Najpierw potwierdź swój adres e-mail.',
        ),
        DisplayNameChangeFailure.invalidName => _copy.text(
          error.message,
          'Podaj prawidłową nazwę wyświetlaną.',
        ),
        DisplayNameChangeFailure.signedOut => _copy.text(
          error.message,
          'Sesja wygasła. Zaloguj się ponownie.',
        ),
        DisplayNameChangeFailure.inactiveAccount => _copy.text(
          error.message,
          'To konto nie może teraz zmienić nazwy wyświetlanej.',
        ),
        DisplayNameChangeFailure.missingProfile => _copy.text(
          error.message,
          'Nie udało się odnaleźć profilu.',
        ),
        DisplayNameChangeFailure.tooManyAttempts => _copy.text(
          error.message,
          'Zbyt wiele prób. Odczekaj chwilę i spróbuj ponownie.',
        ),
        DisplayNameChangeFailure.unavailable => _copy.text(
          error.message,
          'Zmiana nazwy jest chwilowo niedostępna. Spróbuj ponownie.',
        ),
      };
    }

    final message = error.toString();
    if (error is ArgumentError) {
      return _copy.text(
        'Those profile details could not be saved. Check the fields and try again.',
        'Nie udało się zapisać tych danych. Sprawdź pola i spróbuj ponownie.',
      );
    }
    if (message.contains('object-not-found')) {
      return _copy.text(
        "We couldn't find that image on our servers. Please try again.",
        'Nie znaleźliśmy tego obrazu na serwerze. Spróbuj ponownie.',
      );
    }
    if (message.contains('unauthorized') ||
        message.contains('permission-denied')) {
      return _copy.text(
        "You don't have permission to update this profile.",
        'Nie masz uprawnień do aktualizacji tego profilu.',
      );
    }
    if (message.contains('canceled')) {
      return _copy.text('Upload cancelled.', 'Przesyłanie anulowane.');
    }
    if (message.contains('retry-limit') || message.contains('network')) {
      return _copy.text(
        'Upload failed. Please check your connection and try again.',
        'Nie udało się przesłać pliku. Sprawdź połączenie i spróbuj ponownie.',
      );
    }
    return _copy.text(
      'Upload failed. Please try again.',
      'Nie udało się przesłać pliku. Spróbuj ponownie.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        foregroundColor: palette.textPrimary,
        title: Text(copy.text('Edit profile', 'Edytuj profil')),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(
              _saving
                  ? copy.text('Saving...', 'Zapisywanie…')
                  : copy.text('Save', 'Zapisz'),
            ),
          ),
        ],
      ),
      // The whole form is width-constrained: on a laptop this screen used
      // to stretch edge to edge, which blew the 16:9 banner preview up to
      // ~800px tall ("the banner is enormous"). 640 keeps the preview a
      // compact cover card at every width; mobile is unaffected because
      // phones never reach the cap.
      bottomNavigationBar: const YoKeyboardDoneBar(),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Form(
            key: _formKey,
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
              children: [
                _SectionLabel(copy.text('Profile media', 'Zdjęcia profilu')),
                _ProfileImagePreview(
                  profile: widget.profile,
                  pendingAvatar: _pendingAvatar,
                  pendingBanner: _pendingBanner,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _ImageAction(
                        label: _pendingAvatar == null
                            ? copy.text('Change avatar', 'Zmień awatar')
                            : copy.text('Avatar ready', 'Awatar gotowy'),
                        icon: Icons.account_circle_outlined,
                        loading: _pickingAvatar,
                        onTap: () => _pick(ProfileImageKind.avatar),
                        onClear: _pendingAvatar == null
                            ? null
                            : () => _clearPending(ProfileImageKind.avatar),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ImageAction(
                        label: _pendingBanner == null
                            ? copy.text('Change banner', 'Zmień baner')
                            : copy.text('Banner ready', 'Baner gotowy'),
                        icon: Icons.panorama_outlined,
                        loading: _pickingBanner,
                        onTap: () => _pick(ProfileImageKind.banner),
                        onClear: _pendingBanner == null
                            ? null
                            : () => _clearPending(ProfileImageKind.banner),
                      ),
                    ),
                  ],
                ),
                if (_hasPendingImages) ...[
                  const SizedBox(height: 10),
                  Text(
                    copy.text(
                      'New images are applied when you press Save.',
                      'Nowe zdjęcia zostaną zastosowane po naciśnięciu Zapisz.',
                    ),
                    style: TextStyle(color: colors.primary, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 26),
                _SectionLabel(copy.text('Identity', 'Tożsamość')),
                _field(
                  _displayName,
                  copy.text('Display name', 'Nazwa wyświetlana'),
                  required: true,
                  readOnly: !_canChangeDisplayName,
                  helper: _displayNameHelper(context),
                  validator: _validateDisplayName,
                  semanticLabel: _displayNameSemanticLabel(context),
                ),
                _field(
                  _username,
                  copy.text('Username', 'Nazwa użytkownika'),
                  required: true,
                ),
                // The "vibe" line — the profile's social headline, shown
                // on previews and search results. Website was demoted to
                // an About-you detail in its favor.
                _field(
                  _statusMessage,
                  'Vibe',
                  hint: copy.text(
                    'Music + late night talks · Gaming tonight 🎮',
                    'Muzyka i nocne rozmowy · Dziś gram 🎮',
                  ),
                  maxLength: 80,
                ),
                _field(
                  _bio,
                  copy.text('Bio', 'O mnie'),
                  maxLines: 4,
                  maxLength: 220,
                ),
                StreamBuilder<SubscriptionEntitlements>(
                  stream: _entitlements,
                  builder: (context, entitlementSnapshot) {
                    final entitlements =
                        entitlementSnapshot.data ??
                        SubscriptionEntitlements.free;
                    return _AccountTypePicker(
                      value: _accountType,
                      creatorLocked: !entitlements.canUseCreator,
                      creatorPaused:
                          _accountType == AccountType.creator &&
                          !entitlements.canUseCreator,
                      onChanged: (value) {
                        // Creator is a Premium capability. A free member
                        // selecting it gets the explanation + Explore
                        // Premium path — the segment itself never
                        // silently no-ops. (firestore.rules enforces the
                        // same gate server-side; this is the UX layer.)
                        if (value == AccountType.creator &&
                            !entitlements.canUseCreator) {
                          showPremiumUpsellSheet(
                            context,
                            upsellContext: PremiumUpsellContext.creator,
                          );
                          return;
                        }
                        setState(() {
                          _accountType = value;
                        });
                      },
                    );
                  },
                ),
                const SizedBox(height: 26),
                _SectionLabel(copy.text('About you', 'O Tobie')),
                _field(_country, copy.text('Country', 'Kraj')),
                _field(
                  _nativeLanguage,
                  copy.text('Native language', 'Język ojczysty'),
                ),
                _field(
                  _spokenLanguages,
                  copy.text('Languages you speak', 'Języki, którymi mówisz'),
                  hint: copy.text('English, Polish', 'Angielski, polski'),
                ),
                _field(
                  _learningLanguages,
                  copy.text(
                    'Languages you are learning',
                    'Języki, których się uczysz',
                  ),
                  hint: copy.text('Spanish, Dutch', 'Hiszpański, niderlandzki'),
                ),
                _field(_website, copy.text('Website', 'Strona internetowa')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    bool required = false,
    int maxLines = 1,
    int? maxLength,
    bool readOnly = false,
    String? helper,
    String? Function(String?)? validator,
    String? semanticLabel,
  }) {
    final palette = context.appPalette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Semantics(
        label: semanticLabel,
        textField: true,
        readOnly: readOnly,
        child: TextFormField(
          controller: controller,
          maxLines: maxLines,
          maxLength: maxLength,
          readOnly: readOnly,
          style: TextStyle(color: palette.textPrimary),
          validator:
              validator ??
              (required
                  ? (value) => value?.trim().isEmpty == true
                        ? _copy.text('Required', 'Pole wymagane')
                        : null
                  : null),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            helperText: helper,
            // At 200% text a localized date and time can legitimately wrap
            // across several lines on a 320px phone. Keep the full server
            // boundary visible instead of silently ellipsizing it.
            helperMaxLines: 8,
            suffixIcon: readOnly
                ? Icon(
                    Icons.lock_clock_rounded,
                    semanticLabel: _copy.text(
                      'Change limit active',
                      'Aktywny limit zmian',
                    ),
                  )
                : null,
            labelStyle: TextStyle(color: palette.textSecondary),
            hintStyle: TextStyle(color: palette.textTertiary),
            helperStyle: TextStyle(color: palette.textSecondary),
            filled: true,
            fillColor: palette.surfaceRaised,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: palette.borderStrong),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: palette.borderStrong),
            ),
          ),
        ),
      ),
    );
  }

  String? _validateDisplayName(String? value) {
    final trimmed = value?.trim() ?? '';
    final length = trimmed.runes.length;
    if (length < 2) {
      return _copy.text(
        'Use at least 2 characters.',
        'Wpisz co najmniej 2 znaki.',
      );
    }
    if (length > 120) {
      return _copy.text(
        'Use no more than 120 characters.',
        'Wpisz nie więcej niż 120 znaków.',
      );
    }
    if (trimmed.runes.any(_isControlOrFormatCodePoint)) {
      return _copy.text(
        'Remove line breaks or control characters.',
        'Usuń znaki nowego wiersza i znaki sterujące.',
      );
    }
    return null;
  }

  bool _isControlOrFormatCodePoint(int value) {
    return value <= 0x1F ||
        (value >= 0x7F && value <= 0x9F) ||
        value == 0x00AD ||
        (value >= 0x0600 && value <= 0x0605) ||
        value == 0x061C ||
        value == 0x06DD ||
        value == 0x070F ||
        (value >= 0x0890 && value <= 0x0891) ||
        value == 0x08E2 ||
        value == 0x180E ||
        (value >= 0x200B && value <= 0x200F) ||
        (value >= 0x2028 && value <= 0x202E) ||
        (value >= 0x2060 && value <= 0x206F) ||
        value == 0xFEFF ||
        (value >= 0xFFF9 && value <= 0xFFFB) ||
        value == 0x110BD ||
        value == 0x110CD ||
        (value >= 0x13430 && value <= 0x1343F) ||
        (value >= 0x1BCA0 && value <= 0x1BCA3) ||
        (value >= 0x1D173 && value <= 0x1D17A) ||
        value == 0xE0001 ||
        (value >= 0xE0020 && value <= 0xE007F);
  }

  String _displayNameHelper(BuildContext context) {
    if (_displayNameSyncPending) {
      return _copy.text(
        'Name saved. Press Save again to finish account sync.',
        'Nazwa została zapisana. Naciśnij Zapisz ponownie, aby dokończyć synchronizację konta.',
      );
    }
    final next = _nextDisplayNameChangeAt;
    if (next != null && _now.isBefore(next)) {
      return _copy.text(
        'You can change this again ${_formatDateTime(context, next)}.',
        'Nazwę możesz zmienić ponownie ${_formatDateTime(context, next)}.',
      );
    }
    return _copy.text(
      'You can change this once every 30 days.',
      'Nazwę możesz zmienić raz na 30 dni.',
    );
  }

  String _displayNameSemanticLabel(BuildContext context) => _copy.text(
    'Display name. ${_displayNameHelper(context)}',
    'Nazwa wyświetlana. ${_displayNameHelper(context)}',
  );

  void _scheduleDisplayNameCooldownRefresh() {
    _displayNameCooldownTimer?.cancel();
    final next = _nextDisplayNameChangeAt;
    if (next == null || !_now.isBefore(next)) return;
    final delay = next.difference(_now);
    _displayNameCooldownTimer = Timer(delay, () {
      if (!mounted) return;
      setState(() {});
      // A custom/test clock may not advance in lockstep with Timer. Reschedule
      // fail-closed if the authoritative boundary is still in the future.
      _scheduleDisplayNameCooldownRefresh();
    });
  }

  String _formatDateTime(BuildContext context, DateTime value) {
    final local = value.toLocal();
    final localizations = MaterialLocalizations.of(context);
    final date = localizations.formatMediumDate(local);
    final time = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(local),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return _copy.text('on $date at $time', '$date o $time');
  }
}

/// Section heading used to break the form into Profile media / Identity /
/// About you instead of one undifferentiated field list.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: palette.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

/// Live preview of what Save will publish, built on the same shared
/// [ProfileBanner]/[UserAvatar] widgets the Profile screen renders with —
/// so the preview and the real profile literally cannot drift apart.
/// Pending picks render straight from memory, so a newly chosen image
/// appears instantly with no upload and no network round trip.
class _ProfileImagePreview extends StatelessWidget {
  const _ProfileImagePreview({
    required this.profile,
    required this.pendingAvatar,
    required this.pendingBanner,
  });

  final UserProfile profile;
  final PickedProfileImage? pendingAvatar;
  final PickedProfileImage? pendingBanner;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final pendingBannerBytes = pendingBanner?.bytes;
    final pendingAvatarBytes = pendingAvatar?.bytes;

    return AspectRatio(
      // 21:9 preview: reads as a cover card, and inside the form's 640px
      // cap it never exceeds ~275px tall on any screen.
      aspectRatio: 21 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (pendingBannerBytes != null)
              Image.memory(pendingBannerBytes, fit: BoxFit.cover)
            else
              ProfileBanner(
                userId: profile.uid,
                bannerUrl: profile.bannerUrl,
                mediaRevision: profile.profileUpdatedAt,
              ),
            Positioned(
              left: 16,
              bottom: 16,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [colors.primary, colors.secondary],
                  ),
                ),
                child: pendingAvatarBytes != null
                    ? ClipOval(
                        child: Image.memory(
                          pendingAvatarBytes,
                          width: 68,
                          height: 68,
                          fit: BoxFit.cover,
                        ),
                      )
                    : UserAvatar(
                        radius: 34,
                        userId: profile.uid,
                        photoUrl: profile.photoUrl,
                        mediaRevision: profile.profileUpdatedAt,
                        displayName: profile.displayName,
                        backgroundColor: palette.surfaceSunken,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageAction extends StatelessWidget {
  const _ImageAction({
    required this.label,
    required this.icon,
    required this.loading,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final IconData icon;
  final bool loading;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(18),
        // Compact ROW, not a tall tile: these are two small controls, and
        // the old stacked-icon-over-label blocks dominated the form for
        // what is a secondary action. Pick / crop / validate / upload
        // behaviour behind them is unchanged.
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: palette.borderStrong),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              if (loading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  onClear == null ? icon : Icons.check_circle_rounded,
                  size: 20,
                  color: colors.primary,
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (onClear != null)
                IconButton(
                  onPressed: onClear,
                  visualDensity: VisualDensity.compact,
                  tooltip: copy.text('Undo', 'Cofnij'),
                  icon: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: palette.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountTypePicker extends StatelessWidget {
  const _AccountTypePicker({
    required this.value,
    required this.onChanged,
    required this.creatorLocked,
    this.creatorPaused = false,
  });

  final AccountType value;
  final ValueChanged<AccountType> onChanged;
  final bool creatorLocked;

  /// True when the profile is Creator but Premium has lapsed: the
  /// Creator identity and data stay intact, premium Creator tools are
  /// paused until Premium returns (ADR-024 expiration policy).
  final bool creatorPaused;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            copy.text('Account type', 'Typ konta'),
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            copy.text(
              'Creator accounts are prepared for public followers, podcasts and creator tools.',
              'Konta twórców są przeznaczone do budowania publicznej społeczności, podcastów i narzędzi twórcy.',
            ),
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<AccountType>(
            segments: [
              ButtonSegment(
                value: AccountType.personal,
                icon: const Icon(Icons.person_rounded),
                label: Text(copy.text('Personal', 'Osobiste')),
              ),
              ButtonSegment(
                value: AccountType.creator,
                icon: Icon(
                  creatorLocked
                      ? Icons.lock_rounded
                      : Icons.auto_awesome_rounded,
                  key: creatorLocked
                      ? const ValueKey('creator-premium-lock')
                      : null,
                ),
                label: Text(copy.text('Creator', 'Twórca')),
              ),
            ],
            selected: <AccountType>{
              value == AccountType.official ? AccountType.creator : value,
            },
            onSelectionChanged: (selection) => onChanged(selection.first),
            showSelectedIcon: false,
          ),
          if (creatorLocked && !creatorPaused) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.workspace_premium_rounded,
                  color: colors.primary,
                  size: 16,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    copy.text(
                      'Premium is required to activate Creator.',
                      'Do aktywacji konta twórcy wymagane jest Premium.',
                    ),
                    key: ValueKey('creator-premium-required'),
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (value == AccountType.official) ...[
            const SizedBox(height: 10),
            Text(
              copy.text(
                'Official status is verified by YO Voice and cannot be selected manually.',
                'Status oficjalny jest weryfikowany przez YO Voice i nie można wybrać go samodzielnie.',
              ),
              style: TextStyle(color: colors.primary, fontSize: 11),
            ),
          ],
          if (creatorPaused) ...[
            const SizedBox(height: 10),
            Text(
              copy.text(
                'Creator tools are paused — your Premium subscription has '
                    'ended. Your Studio data stays safe. Renew Premium, then '
                    'reactivate Creator in Edit profile.',
                'Narzędzia twórcy są wstrzymane, ponieważ subskrypcja Premium wygasła. '
                    'Dane w Studio są bezpieczne. Odnów Premium, a następnie ponownie aktywuj '
                    'konto twórcy w edycji profilu.',
              ),
              style: TextStyle(color: colors.error, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}
