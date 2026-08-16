import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:yovoice/features/premium/data/models/subscription_entitlements.dart';
import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/features/premium/presentation/widgets/premium_upsell_sheet.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/image_crop.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/profile/presentation/screens/image_crop_screen.dart';
import 'package:yovoice/shared/widgets/profile/profile_banner.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    required this.profile,
    this.service,
    this.entitlements,
    super.key,
  });

  final UserProfile profile;

  /// Injectable so the end-to-end save test (test/profile_save_e2e_test.dart)
  /// can drive THIS screen's real pick→validate→upload→persist pipeline
  /// against mock Firebase backends. Production callers pass nothing.
  final ProfileService? service;

  /// Injectable for the premium-gating tests.
  final EntitlementService? entitlements;

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
  }

  @override
  void dispose() {
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
        const SnackBar(
          content: Text('Please fix the highlighted fields before saving.'),
        ),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
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

      // Images first: if an upload fails the text edits are not committed
      // either, so the user is never left with a half-applied save.
      final avatar = _pendingAvatar;
      if (avatar != null) {
        await _service.uploadProfileImage(avatar);
      }
      final banner = _pendingBanner;
      if (banner != null) {
        await _service.uploadProfileImage(banner);
      }

      await _service.updateProfile(
        displayName: _displayName.text,
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
      messenger.showSnackBar(const SnackBar(content: Text('Profile saved.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyUploadError(error))));
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
      final cropped = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute<Uint8List>(
          builder: (_) => ImageCropScreen(image: decoded, kind: kind),
        ),
      );
      decoded.dispose();
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
        ).showSnackBar(SnackBar(content: Text(_friendlyUploadError(error))));
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
  String _friendlyUploadError(Object error) {
    if (error is ProfileImageException) return error.message;

    final message = error.toString();
    if (error is ArgumentError) {
      return message.replaceFirst('Invalid argument(s): ', '');
    }
    if (message.contains('object-not-found')) {
      return "We couldn't find that image on our servers. Please try again.";
    }
    if (message.contains('unauthorized') ||
        message.contains('permission-denied')) {
      return "You don't have permission to update this profile.";
    }
    if (message.contains('canceled')) {
      return 'Upload cancelled.';
    }
    if (message.contains('retry-limit') || message.contains('network')) {
      return 'Upload failed. Please check your connection and try again.';
    }
    return 'Upload failed. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF09050F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF09050F),
        foregroundColor: Colors.white,
        title: const Text('Edit profile'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving...' : 'Save'),
          ),
        ],
      ),
      // The whole form is width-constrained: on a laptop this screen used
      // to stretch edge to edge, which blew the 16:9 banner preview up to
      // ~800px tall ("the banner is enormous"). 640 keeps the preview a
      // compact cover card at every width; mobile is unaffected because
      // phones never reach the cap.
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
              children: [
                const _SectionLabel('Profile media'),
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
                            ? 'Change avatar'
                            : 'Avatar ready',
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
                            ? 'Change banner'
                            : 'Banner ready',
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
                  const Text(
                    'New images are applied when you press Save.',
                    style: TextStyle(color: Color(0xFFD3A5FF), fontSize: 12),
                  ),
                ],
                const SizedBox(height: 26),
                const _SectionLabel('Identity'),
                _field(_displayName, 'Display name', required: true),
                _field(_username, 'Username', required: true),
                // The "vibe" line — the profile's social headline, shown
                // on previews and search results. Website was demoted to
                // an About-you detail in its favor.
                _field(
                  _statusMessage,
                  'Vibe',
                  hint: 'Music + late night talks · Gaming tonight 🎮',
                  maxLength: 80,
                ),
                _field(_bio, 'Bio', maxLines: 4, maxLength: 220),
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
                const _SectionLabel('About you'),
                _field(_country, 'Country'),
                _field(_nativeLanguage, 'Native language'),
                _field(
                  _spokenLanguages,
                  'Languages you speak',
                  hint: 'English, Polish',
                ),
                _field(
                  _learningLanguages,
                  'Languages you are learning',
                  hint: 'Spanish, Dutch',
                ),
                _field(_website, 'Website'),
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
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        maxLength: maxLength,
        style: const TextStyle(color: Colors.white),
        validator: required
            ? (value) => value?.trim().isEmpty == true ? 'Required' : null
            : null,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: const TextStyle(color: Color(0xFFB3A7BC)),
          hintStyle: const TextStyle(color: Color(0xFF766B80)),
          filled: true,
          fillColor: const Color(0xFF17101F),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF3B2B48)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF3B2B48)),
          ),
        ),
      ),
    );
  }
}

/// Section heading used to break the form into Profile media / Identity /
/// About you instead of one undifferentiated field list.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFF9E92A8),
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
              ProfileBanner(bannerUrl: profile.bannerUrl),
            Positioned(
              left: 16,
              bottom: 16,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFF6A00FF), Color(0xFFD12CFF)],
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
                        photoUrl: profile.photoUrl,
                        displayName: profile.displayName,
                        backgroundColor: const Color(0xFF281133),
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
    return Material(
      color: const Color(0xFF17101F),
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
            border: Border.all(color: const Color(0xFF3B2B48)),
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
                  color: const Color(0xFFB33BFF),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (onClear != null)
                IconButton(
                  onPressed: onClear,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Undo',
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: Color(0xFF9E92A8),
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF17101F),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF3B2B48)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Account type',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Creator accounts are prepared for public followers, podcasts and creator tools.',
            style: TextStyle(
              color: Color(0xFF9E92A8),
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<AccountType>(
            segments: [
              const ButtonSegment(
                value: AccountType.personal,
                icon: Icon(Icons.person_rounded),
                label: Text('Personal'),
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
                label: const Text('Creator'),
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
            const Row(
              children: [
                Icon(
                  Icons.workspace_premium_rounded,
                  color: Color(0xFFFFC24D),
                  size: 16,
                ),
                SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Premium is required to activate Creator.',
                    key: ValueKey('creator-premium-required'),
                    style: TextStyle(
                      color: Color(0xFFFFD985),
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
            const Text(
              'Official status is verified by YO Voice and cannot be selected manually.',
              style: TextStyle(color: Color(0xFFD3A5FF), fontSize: 11),
            ),
          ],
          if (creatorPaused) ...[
            const SizedBox(height: 10),
            const Text(
              'Creator tools are paused — your Premium subscription has '
              'ended. Your Creator profile and data are safe and unlock '
              'again with Premium.',
              style: TextStyle(color: Color(0xFFFFB547), fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}
