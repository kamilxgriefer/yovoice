import 'package:flutter/material.dart';

import '../../data/models/user_profile.dart';
import '../../data/services/profile_service.dart';

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
      await _service.pickAndUploadImage(kind);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
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
