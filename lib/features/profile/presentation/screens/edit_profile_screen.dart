import 'package:flutter/material.dart';

import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({required this.profile, super.key});

  final UserProfile profile;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _service = ProfileService();
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _displayName;
  late final TextEditingController _username;
  late final TextEditingController _bio;
  late final TextEditingController _country;
  late final TextEditingController _nativeLanguage;
  late final TextEditingController _spokenLanguages;
  late final TextEditingController _learningLanguages;
  late final TextEditingController _website;

  bool _saving = false;
  bool _uploadingAvatar = false;
  bool _uploadingBanner = false;
  late AccountType _accountType;

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    _displayName = TextEditingController(text: profile.displayName);
    _username = TextEditingController(text: profile.username);
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
    if (!_formKey.currentState!.validate() || _saving) return;

    setState(() => _saving = true);
    try {
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
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _upload(ProfileImageKind kind) async {
    final avatar = kind == ProfileImageKind.avatar;
    setState(() {
      if (avatar) {
        _uploadingAvatar = true;
      } else {
        _uploadingBanner = true;
      }
    });

    try {
      final url = await _service.pickAndUploadImage(kind);
      if (!mounted || url == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(avatar ? 'Avatar updated.' : 'Banner updated.')),
      );
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
            _uploadingAvatar = false;
          } else {
            _uploadingBanner = false;
          }
        });
      }
    }
  }

  String _friendlyUploadError(Object error) {
    final message = error.toString();
    if (message.contains('object-not-found')) {
      return 'Storage could not find the uploaded image. Deploy storage rules, then try again.';
    }
    if (message.contains('unauthorized')) {
      return 'Storage blocked this upload. Deploy storage rules and make sure you are signed in.';
    }
    if (message.contains('canceled')) {
      return 'Image upload was cancelled.';
    }
    return message;
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
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
          children: [
            Row(
              children: [
                Expanded(
                  child: _ImageAction(
                    label: 'Change avatar',
                    icon: Icons.account_circle_outlined,
                    loading: _uploadingAvatar,
                    onTap: () => _upload(ProfileImageKind.avatar),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ImageAction(
                    label: 'Change banner',
                    icon: Icons.panorama_outlined,
                    loading: _uploadingBanner,
                    onTap: () => _upload(ProfileImageKind.banner),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _AccountTypePicker(
              value: _accountType,
              onChanged: (value) {
                setState(() {
                  _accountType = value;
                });
              },
            ),
            const SizedBox(height: 14),
            _field(_displayName, 'Display name', required: true),
            _field(_username, 'Username', required: true),
            _field(_bio, 'Bio', maxLines: 4, maxLength: 220),
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

class _ImageAction extends StatelessWidget {
  const _ImageAction({
    required this.label,
    required this.icon,
    required this.loading,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF17101F),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF3B2B48)),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              if (loading)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(icon, color: const Color(0xFFB33BFF)),
              const SizedBox(height: 9),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
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
  const _AccountTypePicker({required this.value, required this.onChanged});

  final AccountType value;
  final ValueChanged<AccountType> onChanged;

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
            'Creator accounts are prepared for public followers, broadcasts and creator tools.',
            style: TextStyle(
              color: Color(0xFF9E92A8),
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<AccountType>(
            segments: const [
              ButtonSegment(
                value: AccountType.personal,
                icon: Icon(Icons.person_rounded),
                label: Text('Personal'),
              ),
              ButtonSegment(
                value: AccountType.creator,
                icon: Icon(Icons.auto_awesome_rounded),
                label: Text('Creator'),
              ),
            ],
            selected: <AccountType>{
              value == AccountType.official ? AccountType.creator : value,
            },
            onSelectionChanged: (selection) => onChanged(selection.first),
            showSelectedIcon: false,
          ),
          if (value == AccountType.official) ...[
            const SizedBox(height: 10),
            const Text(
              'Official status is verified by YoVoice and cannot be selected manually.',
              style: TextStyle(color: Color(0xFFD3A5FF), fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}
