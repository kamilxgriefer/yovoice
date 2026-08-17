import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/marketing/data/services/public_showcase_consent_service.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';

class ClubSettingsScreen extends StatefulWidget {
  const ClubSettingsScreen({required this.club, super.key});

  final Club club;

  @override
  State<ClubSettingsScreen> createState() => _ClubSettingsScreenState();
}

class _ClubSettingsScreenState extends State<ClubSettingsScreen> {
  final ClubService _service = ClubService();
  final PublicShowcaseConsentService _showcaseConsentService =
      PublicShowcaseConsentService();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _language;
  late ClubPrivacy _privacy;
  bool _saving = false;
  bool _showOnWebsite = false;
  bool _loadedShowcaseConsent = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.club.name);
    _description = TextEditingController(text: widget.club.description);
    _language = TextEditingController(text: widget.club.defaultLanguage);
    _privacy = widget.club.privacy;
    if (_canControlShowcase) {
      _showcaseConsentService
          .watchClubConsent(
            clubId: widget.club.id,
            ownerId: widget.club.ownerId,
          )
          .first
          .then<void>(
            (value) {
              if (!mounted) return;
              setState(() {
                _showOnWebsite = value;
                _loadedShowcaseConsent = true;
              });
            },
            onError: (Object _, StackTrace __) {
              if (!mounted) return;
              setState(() {
                _showOnWebsite = false;
                _loadedShowcaseConsent = true;
              });
            },
          );
    }
  }

  bool get _canControlShowcase =>
      !widget.club.isFamilyRoom &&
      FirebaseAuth.instance.currentUser?.uid == widget.club.ownerId;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _language.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _service.updateClubDetails(
        clubId: widget.club.id,
        name: _name.text,
        description: _description.text,
        defaultLanguage: _language.text,
        privacy: _privacy,
      );
      if (_canControlShowcase) {
        await _showcaseConsentService.setClubConsent(
          clubId: widget.club.id,
          ownerId: widget.club.ownerId,
          showOnWebsite: _privacy == ClubPrivacy.public && _showOnWebsite,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Club settings saved.')));
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080711),
      appBar: AppBar(
        backgroundColor: const Color(0xFF080711),
        foregroundColor: Colors.white,
        title: const Text('Club settings'),
      ),
      body: ResponsiveContentFrame(
        width: ResponsiveContentWidth.form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 120),
          children: [
            _field(_name, 'Club name'),
            const SizedBox(height: 14),
            _field(_description, 'Description', maxLines: 4),
            const SizedBox(height: 14),
            _field(_language, 'Default language'),
            const SizedBox(height: 20),
            const Text(
              'Privacy',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            ...ClubPrivacy.values.map((privacy) {
              final isSelected = _privacy == privacy;

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: const Color(0xFF171120),
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    onTap: () => setState(() => _privacy = privacy),
                    borderRadius: BorderRadius.circular(16),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 15,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF9D20FF)
                              : const Color(0xFF30263F),
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSelected
                                  ? const Color(0xFF9D20FF)
                                  : Colors.transparent,
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF9D20FF)
                                    : const Color(0xFF756D82),
                                width: 2,
                              ),
                            ),
                            child: isSelected
                                ? const Icon(
                                    Icons.check_rounded,
                                    color: Colors.white,
                                    size: 15,
                                  )
                                : null,
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Text(
                              _privacyLabel(privacy),
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: isSelected
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
            if (_canControlShowcase) ...[
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF171120),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF30263F)),
                ),
                child: SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value:
                      _loadedShowcaseConsent &&
                      _privacy == ClubPrivacy.public &&
                      _showOnWebsite,
                  onChanged:
                      !_loadedShowcaseConsent || _privacy != ClubPrivacy.public
                      ? null
                      : (value) => setState(() => _showOnWebsite = value),
                  title: const Text(
                    'Feature this Club on the YO Voice website',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  subtitle: Text(
                    _privacy == ClubPrivacy.public
                        ? 'Publishes only the Club name and current member count. Family and private Clubs are never included.'
                        : 'Make the Club public before featuring it on the website.',
                    style: const TextStyle(
                      color: Color(0xFFB6ACBB),
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF9D20FF),
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
              ),
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_rounded),
              label: Text(
                _saving ? 'SAVING...' : 'SAVE SETTINGS',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFFB6ACBB)),
        filled: true,
        fillColor: const Color(0xFF171120),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(17)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: const BorderSide(color: Color(0xFF3A2D46)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: const BorderSide(color: Color(0xFF9D20FF)),
        ),
      ),
    );
  }

  String _privacyLabel(ClubPrivacy privacy) => switch (privacy) {
    ClubPrivacy.public => 'Public',
    ClubPrivacy.private => 'Private',
    ClubPrivacy.inviteOnly => 'Invite only',
  };
}
