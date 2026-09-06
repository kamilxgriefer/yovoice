import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/marketing/data/services/public_showcase_consent_service.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/inputs/yo_keyboard_done_bar.dart';

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(
              context,
            ).text('Club settings saved.', 'Zapisano ustawienia klubu.'),
          ),
        ),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      final copy = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(
              error,
              fallback: copy.text(
                'Could not save settings. Please try again.',
                'Nie udało się zapisać ustawień. Spróbuj ponownie.',
              ),
              copy: copy,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);
    return Scaffold(
      key: const ValueKey('club-settings-screen'),
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        foregroundColor: palette.textPrimary,
        title: Text(copy.text('Club settings', 'Ustawienia klubu')),
      ),
      bottomNavigationBar: const YoKeyboardDoneBar(),
      body: ResponsiveContentFrame(
        width: ResponsiveContentWidth.form,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 120),
          children: [
            _field(_name, copy.text('Club name', 'Nazwa klubu')),
            const SizedBox(height: 14),
            _field(_description, copy.text('Description', 'Opis'), maxLines: 4),
            const SizedBox(height: 14),
            _field(_language, copy.text('Default language', 'Domyślny język')),
            const SizedBox(height: 20),
            Text(
              copy.text('Privacy', 'Prywatność'),
              style: TextStyle(
                color: palette.textPrimary,
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
                  color: palette.surface,
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
                          color: isSelected ? colors.primary : palette.border,
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
                                  ? colors.primary
                                  : Colors.transparent,
                              border: Border.all(
                                color: isSelected
                                    ? colors.primary
                                    : palette.borderStrong,
                                width: 2,
                              ),
                            ),
                            child: isSelected
                                ? Icon(
                                    Icons.check_rounded,
                                    color: colors.onPrimary,
                                    size: 15,
                                  )
                                : null,
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Text(
                              _privacyLabel(privacy, copy),
                              style: TextStyle(
                                color: palette.textPrimary,
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
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: palette.border),
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
                  title: Text(
                    copy.text(
                      'Feature this Club on the YO Voice website',
                      'Pokaż ten klub na stronie YO Voice',
                    ),
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  subtitle: Text(
                    _privacy == ClubPrivacy.public
                        ? copy.text(
                            'Publishes only the Club name and current member count. Family and private Clubs are never included.',
                            'Publikujemy wyłącznie nazwę klubu i aktualną liczbę członków. Pokoje rodzinne i prywatne kluby nigdy nie są uwzględniane.',
                          )
                        : copy.text(
                            'Make the Club public before featuring it on the website.',
                            'Najpierw ustaw klub jako publiczny.',
                          ),
                    style: TextStyle(
                      color: palette.textSecondary,
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
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
              ),
              icon: _saving
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.onPrimary,
                      ),
                    )
                  : const Icon(Icons.save_rounded),
              label: Text(
                _saving
                    ? copy.text('SAVING...', 'ZAPISYWANIE...')
                    : copy.text('SAVE SETTINGS', 'ZAPISZ USTAWIENIA'),
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
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: TextStyle(color: palette.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: palette.textSecondary),
        filled: true,
        fillColor: palette.surfaceRaised,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(17)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: BorderSide(color: palette.borderStrong),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: BorderSide(color: colors.primary),
        ),
      ),
    );
  }

  String _privacyLabel(ClubPrivacy privacy, AppLocalizations copy) =>
      switch (privacy) {
        ClubPrivacy.public => copy.text('Public', 'Publiczny'),
        ClubPrivacy.private => copy.text('Private', 'Prywatny'),
        ClubPrivacy.inviteOnly => copy.text(
          'Invite only',
          'Tylko na zaproszenie',
        ),
      };
}
