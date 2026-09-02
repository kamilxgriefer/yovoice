import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/space_identity.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:image_picker/image_picker.dart';

import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/clubs/presentation/screens/club_created_screen.dart';

class CreateClubScreen extends StatefulWidget {
  const CreateClubScreen({
    this.type = ClubType.community,
    this.clubService,
    super.key,
  });

  /// Which space this screen is creating. A Family Room is the same club
  /// document with a private boundary, so it reuses this whole flow —
  /// only the wording, the accent and the privacy choice differ.
  final ClubType type;

  bool get isFamily => type == ClubType.family;

  /// Injected in tests, exactly as the Home surfaces do it: production
  /// passes nothing and the screen resolves its own, which needs a live
  /// Firebase app.
  final ClubService? clubService;

  @override
  State<CreateClubScreen> createState() => _CreateClubScreenState();
}

class _CreateClubScreenState extends State<CreateClubScreen> {
  /// Every colour on this screen comes from here. The Family flow used to
  /// inherit Club violet wholesale, which is exactly the failure a single
  /// identity source exists to prevent.
  SpaceIdentity get _identity =>
      widget.isFamily ? SpaceIdentity.family : SpaceIdentity.club;

  static const _languages = <String>[
    'English',
    'Polish',
    'Dutch',
    'German',
    'Spanish',
    'French',
    'Italian',
    'Portuguese',
    'Japanese',
    'Korean',
  ];

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  late final ClubService _clubService = widget.clubService ?? ClubService();
  final _picker = ImagePicker();

  ClubPrivacy _privacy = ClubPrivacy.public;
  String _language = 'English';
  bool _busy = false;
  bool _pickingImage = false;
  String? _communityCreationId;

  XFile? _avatarFile;
  XFile? _bannerFile;
  Uint8List? _avatarBytes;
  Uint8List? _bannerBytes;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickImage({required bool avatar}) async {
    if (_busy || _pickingImage) return;
    setState(() => _pickingImage = true);

    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
        maxWidth: avatar ? 1200 : 2200,
        maxHeight: avatar ? 1200 : 1200,
      );
      if (file == null) return;

      final bytes = await file.readAsBytes();
      if (bytes.length > 8 * 1024 * 1024) {
        throw StateError('The selected image must be smaller than 8 MB.');
      }

      if (!mounted) return;
      setState(() {
        if (avatar) {
          _avatarFile = file;
          _avatarBytes = bytes;
        } else {
          _bannerFile = file;
          _bannerBytes = bytes;
        }
      });
    } catch (error) {
      if (!mounted) return;
      _showError(_readableError(error));
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  Future<void> _createClub() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _busy = true);
    try {
      final club = widget.isFamily
          // Deterministic id, invite-only, no Premium requirement — the
          // service owns those invariants so no caller can get them
          // wrong.
          ? await _clubService.createFamilyRoom(
              name: _nameController.text,
              description: _descriptionController.text,
              defaultLanguage: _language,
            )
          : await _clubService.createClub(
              name: _nameController.text,
              description: _descriptionController.text,
              privacy: _privacy,
              defaultLanguage: _language,
              avatarFile: _avatarFile,
              bannerFile: _bannerFile,
              // Keep one server idempotency key for the lifetime of this
              // form. If the callable commits and its response is lost, the
              // next tap recovers the same Club rather than allocating a
              // second id and consuming another quota slot.
              documentId: _communityCreationId ??= _clubService
                  .newClubDocumentId(),
            );

      if (!mounted) return;
      await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute<void>(builder: (_) => ClubCreatedScreen(club: club)),
      );
    } catch (error) {
      if (!mounted) return;
      _showError(_readableError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _readableError(Object error) {
    final copy = AppLocalizations.of(context);
    final message = error
        .toString()
        .replaceFirst('Bad state: ', '')
        .replaceFirst('Invalid argument(s): ', '');
    if (message.contains('smaller than 8 MB')) {
      return copy.text(
        'The selected image must be smaller than 8 MB.',
        'Wybrane zdjęcie musi mieć mniej niż 8 MB.',
      );
    }
    if (message.contains('permission-denied')) {
      return copy.text(
        'Your account is not allowed to create this space right now. Refresh your session and try again.',
        'Twoje konto nie może teraz utworzyć tej przestrzeni. Odśwież sesję i spróbuj ponownie.',
      );
    }
    if (message.contains('object-not-found')) {
      return copy.text(
        'The uploaded image could not be found.',
        'Nie znaleziono przesłanego zdjęcia.',
      );
    }
    if (message.contains('unauthorized')) {
      return copy.text(
        'The image upload was not authorized. Refresh your session and try again.',
        'Nie udało się przesłać zdjęcia. Odśwież sesję i spróbuj ponownie.',
      );
    }
    return friendlyErrorMessage(
      error,
      copy: copy,
      fallback: copy.text(
        'Could not create this space. Please try again.',
        'Nie udało się utworzyć przestrzeni. Spróbuj ponownie.',
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final identityVisuals = _identity.resolve(colors.brightness);
    final copy = AppLocalizations.of(context);
    return Scaffold(
      key: const ValueKey('create-club-screen'),
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        foregroundColor: palette.textPrimary,
        centerTitle: true,
        title: Text(
          widget.isFamily
              ? copy.text('Create Family Room', 'Utwórz pokój rodzinny')
              : copy.text('Create Club', 'Utwórz klub'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: ResponsiveContentFrame(
        width: ResponsiveContentWidth.form,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 130),
            children: [
              _HeroCard(identity: _identity, isFamily: widget.isFamily),
              const SizedBox(height: 24),
              _SectionTitle(
                title: widget.isFamily
                    ? copy.text('Family identity', 'Tożsamość rodziny')
                    : copy.text('Club identity', 'Tożsamość klubu'),
                subtitle: widget.isFamily
                    ? copy.text(
                        'Name the space your family will recognize.',
                        'Nadaj przestrzeni nazwę rozpoznawalną dla rodziny.',
                      )
                    : copy.text(
                        'Give your people a place they will recognize.',
                        'Stwórz miejsce, które rozpozna Twoja społeczność.',
                      ),
              ),
              const SizedBox(height: 14),
              if (!widget.isFamily)
                Row(
                  children: [
                    Expanded(
                      child: _MediaPickerCard(
                        icon: Icons.groups_2_rounded,
                        label: copy.text('Club avatar', 'Avatar klubu'),
                        helper: _avatarBytes == null
                            ? copy.text('Choose image', 'Wybierz zdjęcie')
                            : copy.text(
                                'Tap to replace',
                                'Dotknij, aby zmienić',
                              ),
                        bytes: _avatarBytes,
                        circularPreview: true,
                        onTap: () => _pickImage(avatar: true),
                        onRemove: _avatarBytes == null
                            ? null
                            : () => setState(() {
                                _avatarFile = null;
                                _avatarBytes = null;
                              }),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _MediaPickerCard(
                        icon: Icons.image_rounded,
                        label: copy.text('Club banner', 'Baner klubu'),
                        helper: _bannerBytes == null
                            ? copy.text('Choose image', 'Wybierz zdjęcie')
                            : copy.text(
                                'Tap to replace',
                                'Dotknij, aby zmienić',
                              ),
                        bytes: _bannerBytes,
                        onTap: () => _pickImage(avatar: false),
                        onRemove: _bannerBytes == null
                            ? null
                            : () => setState(() {
                                _bannerFile = null;
                                _bannerBytes = null;
                              }),
                      ),
                    ),
                  ],
                ),
              if (widget.isFamily) const _PrivateFamilyMediaNotice(),
              const SizedBox(height: 16),
              _Field(
                controller: _nameController,
                label: widget.isFamily
                    ? copy.text('Family name', 'Nazwa rodziny')
                    : copy.text('Club name', 'Nazwa klubu'),
                hint: copy.text(
                  'e.g. YO Voice Founders',
                  'np. Założyciele YO Voice',
                ),
                maxLength: 40,
                validator: (value) {
                  final length = value?.trim().length ?? 0;
                  if (length < 3) {
                    return copy.text(
                      'Enter at least 3 characters',
                      'Wpisz co najmniej 3 znaki',
                    );
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              _Field(
                controller: _descriptionController,
                label: copy.text('Description', 'Opis'),
                hint: copy.text(
                  'What brings this club together?',
                  'Co łączy tę społeczność?',
                ),
                maxLength: 220,
                maxLines: 4,
              ),
              const SizedBox(height: 26),
              // A Family Room has exactly one privacy model, so there is
              // nothing to choose: offering "Public" on a space defined as
              // private would be a lie the service would then ignore.
              if (!widget.isFamily) ...[
                _SectionTitle(
                  title: copy.text('Privacy', 'Prywatność'),
                  subtitle: copy.text(
                    'Choose how new members can enter.',
                    'Wybierz sposób dołączania nowych członków.',
                  ),
                ),
                const SizedBox(height: 14),
                _PrivacyChoice(
                  title: copy.text('Public', 'Publiczny'),
                  subtitle: copy.text(
                    'Anyone can discover and join the club.',
                    'Każdy może znaleźć klub i do niego dołączyć.',
                  ),
                  icon: Icons.public_rounded,
                  value: ClubPrivacy.public,
                  selectedValue: _privacy,
                  onChanged: (value) => setState(() => _privacy = value),
                ),
                const SizedBox(height: 10),
                _PrivacyChoice(
                  title: copy.text('Private', 'Prywatny'),
                  subtitle: copy.text(
                    'The club is hidden and members join by invitation.',
                    'Klub jest ukryty, a członkowie dołączają z zaproszenia.',
                  ),
                  icon: Icons.lock_rounded,
                  value: ClubPrivacy.private,
                  selectedValue: _privacy,
                  onChanged: (value) => setState(() => _privacy = value),
                ),
                const SizedBox(height: 10),
                _PrivacyChoice(
                  title: copy.text('Invite only', 'Tylko na zaproszenie'),
                  subtitle: copy.text(
                    'Visible club, but every member needs an invite.',
                    'Klub jest widoczny, ale dołączenie wymaga zaproszenia.',
                  ),
                  icon: Icons.mail_rounded,
                  value: ClubPrivacy.inviteOnly,
                  selectedValue: _privacy,
                  onChanged: (value) => setState(() => _privacy = value),
                ),
              ],
              const SizedBox(height: 26),
              _SectionTitle(
                title: widget.isFamily
                    ? copy.text(
                        'Primary family language',
                        'Główny język rodziny',
                      )
                    : copy.text('Default language', 'Domyślny język'),
                subtitle: widget.isFamily
                    ? copy.text(
                        'Everyone can still speak any language here.',
                        'Każdy nadal może mówić tutaj w dowolnym języku.',
                      )
                    : copy.text(
                        'Members can still use any language in the club.',
                        'Członkowie nadal mogą używać w klubie dowolnego języka.',
                      ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _language,
                dropdownColor: palette.surfaceRaised,
                iconEnabledColor: identityVisuals.foreground,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: palette.surface,
                  prefixIcon: Icon(
                    Icons.language_rounded,
                    color: identityVisuals.foreground,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide(color: palette.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide(color: palette.border),
                  ),
                ),
                items: _languages
                    .map(
                      (language) => DropdownMenuItem<String>(
                        value: language,
                        child: Text(_languageLabel(language, copy)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value != null) setState(() => _language = value);
                },
              ),
              const SizedBox(height: 24),
              _WhatGetsCreatedCard(isFamily: widget.isFamily),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: palette.surfaceRaised,
            border: Border(top: BorderSide(color: palette.border)),
          ),
          child: ResponsiveContentFrame(
            width: ResponsiveContentWidth.form,
            fillHeight: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              child: SizedBox(
                height: 58,
                child: FilledButton.icon(
                  key: const ValueKey('space-identity-create-cta'),
                  onPressed: _busy || _pickingImage ? null : _createClub,
                  style: FilledButton.styleFrom(
                    backgroundColor: identityVisuals.cta,
                    foregroundColor: identityVisuals.onCta,
                    disabledBackgroundColor: _busy
                        ? identityVisuals.cta
                        : palette.surfaceSunken,
                    disabledForegroundColor: _busy
                        ? identityVisuals.onCta
                        : palette.textTertiary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(19),
                    ),
                  ),
                  icon: _busy
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: identityVisuals.spinner,
                          ),
                        )
                      : const Icon(Icons.add_business_rounded),
                  label: Text(
                    _busy
                        ? (widget.isFamily
                              ? copy.text(
                                  'Creating Family Room...',
                                  'Tworzenie pokoju rodzinnego...',
                                )
                              : copy.text(
                                  'Creating club...',
                                  'Tworzenie klubu...',
                                ))
                        : (widget.isFamily
                              ? copy.text(
                                  'Create Family Room',
                                  'Utwórz pokój rodzinny',
                                )
                              : copy.text('Create Club', 'Utwórz klub')),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _languageLabel(String language, AppLocalizations copy) {
    if (!copy.isPolish) return language;
    return switch (language) {
      'English' => 'Angielski',
      'Polish' => 'Polski',
      'Dutch' => 'Niderlandzki',
      'German' => 'Niemiecki',
      'Spanish' => 'Hiszpański',
      'French' => 'Francuski',
      'Italian' => 'Włoski',
      'Portuguese' => 'Portugalski',
      'Japanese' => 'Japoński',
      'Korean' => 'Koreański',
      _ => language,
    };
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.identity, required this.isFamily});

  final SpaceIdentity identity;
  final bool isFamily;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [palette.surfaceRaised, palette.surface],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ClubMark(identity: identity),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  copy.text(
                    'Build your home on YO Voice',
                    'Zbuduj swoje miejsce w YO Voice',
                  ),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  isFamily
                      ? copy.text(
                          'A private, invite-only space for the people closest to you.',
                          'Prywatna przestrzeń na zaproszenie dla najbliższych osób.',
                        )
                      : copy.text(
                          'A Club is permanent: members, roles, a main chat, announcements and a private voice lounge.',
                          'Klub jest stały: członkowie, role, główny czat, ogłoszenia i prywatny pokój głosowy.',
                        ),
                  style: TextStyle(color: palette.textSecondary, height: 1.42),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivateFamilyMediaNotice extends StatelessWidget {
  const _PrivateFamilyMediaNotice();

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final accent = palette.successForeground;
    final copy = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.successSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: .55)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_rounded, color: accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              copy.text(
                'Family Rooms use private initials for now. Photos stay unavailable until they can be loaded through authenticated private media.',
                'Pokoje rodzinne używają obecnie prywatnych inicjałów. Zdjęcia będą dostępne, gdy możliwe będzie ich bezpieczne wczytywanie jako prywatnych multimediów.',
              ),
              style: TextStyle(color: palette.textSecondary, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClubMark extends StatelessWidget {
  const _ClubMark({required this.identity});

  final SpaceIdentity identity;

  @override
  Widget build(BuildContext context) {
    final visuals = identity.resolve(Theme.of(context).brightness);
    return Container(
      key: const ValueKey('space-identity-mark'),
      width: 62,
      height: 62,
      decoration: BoxDecoration(
        color: visuals.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: visuals.border),
      ),
      child: Icon(identity.icon, color: visuals.onSurface, size: 34),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: 19,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(color: palette.textSecondary, height: 1.35),
        ),
      ],
    );
  }
}

class _MediaPickerCard extends StatelessWidget {
  const _MediaPickerCard({
    required this.icon,
    required this.label,
    required this.helper,
    required this.onTap,
    this.bytes,
    this.circularPreview = false,
    this.onRemove,
  });
  final IconData icon;
  final String label;
  final String helper;
  final VoidCallback onTap;
  final Uint8List? bytes;
  final bool circularPreview;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 150,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: palette.border),
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (bytes == null)
                      Icon(icon, color: colors.primary, size: 32)
                    else
                      ClipRRect(
                        borderRadius: BorderRadius.circular(
                          circularPreview ? 999 : 14,
                        ),
                        child: Image.memory(
                          bytes!,
                          width: circularPreview ? 64 : double.infinity,
                          height: 64,
                          fit: BoxFit.cover,
                        ),
                      ),
                    const SizedBox(height: 10),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      helper,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (onRemove != null)
                Positioned(
                  top: 0,
                  right: 0,
                  child: IconButton.filledTonal(
                    tooltip: AppLocalizations.of(
                      context,
                    ).text('Remove image', 'Usuń zdjęcie'),
                    visualDensity: VisualDensity.compact,
                    onPressed: onRemove,
                    icon: const Icon(Icons.close_rounded, size: 17),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    required this.maxLength,
    this.maxLines = 1,
    this.validator,
  });
  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLength;
  final int maxLines;
  final String? Function(String?)? validator;
  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return TextFormField(
      controller: controller,
      maxLength: maxLength,
      maxLines: maxLines,
      validator: validator,
      style: TextStyle(color: palette.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        counterStyle: TextStyle(color: palette.textTertiary),
        labelStyle: TextStyle(color: palette.textSecondary),
        hintStyle: TextStyle(color: palette.textTertiary),
        filled: true,
        fillColor: palette.surfaceRaised,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: palette.borderStrong),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: colors.primary, width: 1.5),
        ),
      ),
    );
  }
}

class _PrivacyChoice extends StatelessWidget {
  const _PrivacyChoice({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.selectedValue,
    required this.onChanged,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final ClubPrivacy value;
  final ClubPrivacy selectedValue;
  final ValueChanged<ClubPrivacy> onChanged;
  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final selected = value == selectedValue;
    return Material(
      color: selected ? colors.primaryContainer : palette.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: () => onChanged(value),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? colors.primary : palette.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: selected ? colors.primary : palette.textSecondary,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? colors.primary : Colors.transparent,
                  border: Border.all(
                    color: selected ? colors.primary : palette.borderStrong,
                    width: 2,
                  ),
                ),
                child: selected
                    ? Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: colors.onPrimary,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WhatGetsCreatedCard extends StatelessWidget {
  const _WhatGetsCreatedCard({required this.isFamily});

  final bool isFamily;
  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            copy.text('Created automatically', 'Utworzymy automatycznie'),
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          _CreatedItem(
            icon: Icons.tag_rounded,
            text: isFamily
                ? copy.text('Family chat', 'Czat rodzinny')
                : copy.text('General chat', 'Czat ogólny'),
          ),
          _CreatedItem(
            icon: Icons.campaign_rounded,
            text: isFamily
                ? copy.text('Announcements', 'Ogłoszenia')
                : copy.text('Announcements channel', 'Kanał ogłoszeń'),
          ),
          _CreatedItem(
            icon: Icons.graphic_eq_rounded,
            text: isFamily
                ? copy.text('Family Lounge', 'Rodzinny pokój głosowy')
                : copy.text(
                    'Private Club Lounge',
                    'Prywatny klubowy pokój głosowy',
                  ),
          ),
          if (isFamily)
            _CreatedItem(
              icon: Icons.waving_hand_rounded,
              text: copy.text('Quick check-ins', 'Szybkie meldunki'),
            ),
          _CreatedItem(
            icon: Icons.admin_panel_settings_rounded,
            text: isFamily
                ? copy.text(
                    'Organizer role and membership',
                    'Rola organizatora i członkostwo',
                  )
                : copy.text(
                    'Owner role and membership',
                    'Rola właściciela i członkostwo',
                  ),
          ),
        ],
      ),
    );
  }
}

class _CreatedItem extends StatelessWidget {
  const _CreatedItem({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Icon(icon, color: colors.primary, size: 19),
          const SizedBox(width: 10),
          // Unconstrained, this Text overflowed the row on a 390pt phone —
          // the longest of these lines does not fit beside the icon.
          Expanded(
            child: Text(text, style: TextStyle(color: palette.textSecondary)),
          ),
        ],
      ),
    );
  }
}
