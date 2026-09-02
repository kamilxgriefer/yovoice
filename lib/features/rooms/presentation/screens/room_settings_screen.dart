import 'package:flutter/material.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_image_service.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/presentation/room_cover_editor.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/theme/yo_immersive_dark_surface.dart';

const _background = Color(0xFF080711);
const _surface = Color(0xFF151020);
const _border = Color(0xFF392B47);
const _muted = Color(0xFF9D95AD);
const _primary = Color(0xFFA226FF);
const _danger = Color(0xFFFF416C);

class RoomSettingsScreen extends StatefulWidget {
  const RoomSettingsScreen({
    required this.room,
    this.roomService,
    this.roomImageService,
    this.clubService,
    this.coverEditor,
    super.key,
  });

  final VoiceRoom room;
  final RoomService? roomService;
  final RoomImageService? roomImageService;
  final RoomCoverEditorCallback? coverEditor;

  /// Resolves club ownership when [room] is a club lounge. Optional: the
  /// screen constructs its own where Firebase allows; where it cannot, a
  /// lounge simply shows NO delete control — the fail-closed direction.
  final ClubService? clubService;

  @override
  State<RoomSettingsScreen> createState() => _RoomSettingsScreenState();
}

class _RoomSettingsScreenState extends State<RoomSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final RoomService _service = widget.roomService ?? RoomService();
  late final RoomImageService _images =
      widget.roomImageService ?? RoomImageService();

  String? _imageUrl;
  bool _changingCover = false;

  /// The cover is part of the room's identity (stage backdrop + Home/
  /// Discover card). The host first confirms a manual crop; only that final
  /// JPEG is uploaded and published. Lock before opening the picker so a fast
  /// double tap cannot stack pickers/crop screens or race two pointer updates.
  Future<void> _changeCover() async {
    if (_changingCover || _busy) return;
    setState(() => _changingCover = true);
    try {
      final editor = widget.coverEditor ?? RoomCoverEditor.pickAndCrop;
      final cover = await editor(context, _images);
      if (cover == null || !mounted) return;
      final upload = await _images.uploadRoomCover(
        roomId: widget.room.id,
        bytes: cover.bytes,
      );
      try {
        await _service.finalizeRoomCoverUpload(
          roomId: widget.room.id,
          storagePath: upload.storagePath,
          objectGeneration: upload.objectGeneration,
          reservationId: upload.reservationId,
        );
      } catch (error, stackTrace) {
        // A failed write acknowledgement can still mean the pointer committed.
        // Re-read before deleting so cleanup can never break a valid cover.
        var pointerRead = false;
        var committed = false;
        try {
          final canonical = await _service.getRoomFromServer(widget.room.id);
          pointerRead = true;
          committed =
              canonical.coverStoragePath == upload.storagePath &&
              canonical.coverGeneration == upload.objectGeneration;
        } catch (_) {
          // Ambiguous state: preserve the uploaded object and the original
          // error. A later room deletion still cleans the whole prefix.
        }
        if (!committed) {
          if (pointerRead) {
            await _images.deleteManagedRoomCoverPath(
              roomId: widget.room.id,
              storagePath: upload.storagePath,
            );
          }
          Error.throwWithStackTrace(error, stackTrace);
        }
      }
      String? nextImageUrl;
      try {
        nextImageUrl = (await _service.getRoom(widget.room.id)).imageUrl;
      } catch (_) {
        // The canonical pointer already committed. The room stream will
        // retry the short-lived render grant without treating this as an
        // upload failure.
      }
      if (!mounted) return;
      setState(() => _imageUrl = nextImageUrl);
    } catch (error) {
      if (!mounted) return;
      final copy = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            copy.isPolish
                ? 'Nie udało się zaktualizować okładki pokoju. Spróbuj ponownie.'
                : intentionalOrFriendly(
                    error,
                    fallback:
                        "Couldn't update the room cover. Please try again.",
                  ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _changingCover = false);
    }
  }

  late final TextEditingController _name;
  late final TextEditingController _description;
  late String _category;
  late String _visibility;
  late String _language;
  late int? _maxParticipants;
  late bool _approvalRequired;
  late int _slowModeSeconds;
  late bool _autoMuteNewUsers;
  late bool _membersCanStartVoice;

  /// Non-null only when this room is a club lounge whose club document can
  /// be watched. `deleteRoomSelf` refuses `club_lounge_*` rooms outright,
  /// so the delete control for a lounge must be the CLUB delete (owner-only
  /// `deleteClubSelf`) or nothing at all — never the room delete.
  ClubService? _clubService;
  Stream<Club>? _clubStream;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final room = widget.room;
    _name = TextEditingController(text: room.name);
    _description = TextEditingController(text: room.description);
    _imageUrl = room.imageUrl;
    _category = room.category;
    _visibility = room.visibility;
    _language = room.language;
    _maxParticipants = room.maxParticipants;
    _approvalRequired = room.approvalRequired;
    _slowModeSeconds = room.slowModeSeconds;
    _autoMuteNewUsers = room.autoMuteNewUsers;
    _membersCanStartVoice = room.membersCanStartVoice;

    // `storedClubId`, NOT the prefix-derived `clubId`: authority (both
    // deleteClubSelf and the rules' Club branch) reads the document FIELD.
    final clubId = room.storedClubId;
    if (clubId != null) {
      try {
        _clubService = widget.clubService ?? ClubService();
        _clubStream = _clubService!.watchClub(clubId);
      } catch (_) {
        // No Firebase (widget tests, degraded startup): the lounge shows no
        // delete control rather than a broken one.
        _clubService = null;
        _clubStream = null;
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _busy || _changingCover) return;
    setState(() => _busy = true);
    try {
      await _service.updateRoomSettings(
        roomId: widget.room.id,
        name: _name.text,
        description: _description.text,
        category: _category,
        visibility: _visibility,
        language: _language,
        maxParticipants: _maxParticipants,
        approvalRequired: _approvalRequired,
        slowModeSeconds: _slowModeSeconds,
        autoMuteNewUsers: _autoMuteNewUsers,
        membersCanStartVoice: _membersCanStartVoice,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      final copy = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            copy.isPolish
                ? 'Nie udało się zapisać zmian. Spróbuj ponownie.'
                : intentionalOrFriendly(
                    error,
                    fallback: "The change couldn't be saved. Please try again.",
                  ),
          ),
        ),
      );
    }
  }

  Future<void> _setStatus(RoomStatus status) async {
    if (_busy || _changingCover) return;
    final copy = AppLocalizations.of(context);
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: _surface,
            title: Text(switch (status) {
              RoomStatus.active => copy.text('Open room?', 'Otworzyć pokój?'),
              RoomStatus.closed => copy.text('Close room?', 'Zamknąć pokój?'),
              RoomStatus.archived => copy.text(
                'Archive room?',
                'Zarchiwizować pokój?',
              ),
              RoomStatus.suspended => copy.text(
                'Suspend room?',
                'Zawiesić pokój?',
              ),
            }, style: const TextStyle(color: Colors.white)),
            content: Text(
              status == RoomStatus.active
                  ? copy.text(
                      'The room will be visible and usable again.',
                      'Pokój znów będzie widoczny i dostępny.',
                    )
                  : status == RoomStatus.closed
                  ? copy.text(
                      'Members will keep their membership, but voice and chat access can be paused until you reopen it.',
                      'Członkowie zachowają członkostwo, ale rozmowy głosowe i czat mogą być wstrzymane do ponownego otwarcia.',
                    )
                  : copy.text(
                      'The room will be hidden from Discover until you restore it.',
                      'Pokój będzie ukryty w sekcji Odkrywaj, dopóki go nie przywrócisz.',
                    ),
              style: const TextStyle(color: _muted),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(copy.text('Cancel', 'Anuluj')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(switch (status) {
                  RoomStatus.active => copy.text('OPEN', 'OTWÓRZ'),
                  RoomStatus.closed => copy.text('CLOSE', 'ZAMKNIJ'),
                  RoomStatus.archived => copy.text('ARCHIVE', 'ARCHIWIZUJ'),
                  RoomStatus.suspended => copy.text('SUSPEND', 'ZAWIEŚ'),
                }),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || _busy || _changingCover) return;
    setState(() => _busy = true);
    try {
      await _service.setRoomStatus(widget.room.id, status);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            copy.isPolish
                ? 'Nie udało się zmienić statusu pokoju. Spróbuj ponownie.'
                : intentionalOrFriendly(
                    error,
                    fallback:
                        "The room status couldn't change. Please try again.",
                  ),
          ),
        ),
      );
    }
  }

  Future<void> _delete() async {
    // Unrepresentable, not merely unreachable: a club lounge never renders
    // the tile that leads here, and even if one did, this path must not
    // call deleteRoomSelf — the server refuses lounges and the user would
    // get a dialog whose Delete can only ever fail. Lounges go through
    // _deleteClub().
    if (widget.room.storedClubId != null || _busy || _changingCover) return;
    final copy = AppLocalizations.of(context);
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: _surface,
            title: Text(
              copy.text(
                'Delete "${widget.room.name}"?',
                'Usunąć „${widget.room.name}”?',
              ),
              style: const TextStyle(color: Colors.white),
            ),
            content: Text(
              copy.text(
                'Messages, members and room settings will be permanently '
                    'removed. This cannot be undone.',
                'Wiadomości, członkowie i ustawienia pokoju zostaną trwale usunięte. Tej operacji nie można cofnąć.',
              ),
              style: const TextStyle(color: _muted),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(copy.text('Cancel', 'Anuluj')),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _danger),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(copy.text('Delete', 'Usuń')),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || _busy || _changingCover) return;
    setState(() => _busy = true);
    try {
      await _service.deleteRoom(widget.room.id);
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            copy.isPolish
                ? 'Nie udało się usunąć pokoju. Spróbuj ponownie za chwilę.'
                : intentionalOrFriendly(
                    error,
                    fallback:
                        "The room couldn't be deleted. Please try again in a moment.",
                  ),
          ),
        ),
      );
    }
  }

  /// The lounge counterpart of [_delete]: tears down the WHOLE Club through
  /// the owner-only `deleteClubSelf` callable. Same confirm shape, honest
  /// copy — the dialog names the Club and says what actually goes away.
  Future<void> _deleteClub(Club club) async {
    final service = _clubService;
    if (service == null || _busy || _changingCover) return;
    final copy = AppLocalizations.of(context);
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: _surface,
            title: Text(
              copy.text(
                'Delete the Club "${club.name}"?',
                'Usunąć klub „${club.name}”?',
              ),
              style: const TextStyle(color: Colors.white),
            ),
            content: Text(
              copy.text(
                'This deletes the whole Club — its lounge, chat, channels, '
                    'members and invites. This cannot be undone.',
                'Spowoduje to usunięcie całego klubu — jego pokoju głosowego, czatu, kanałów, członków i zaproszeń. Tej operacji nie można cofnąć.',
              ),
              style: const TextStyle(color: _muted),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(copy.text('Cancel', 'Anuluj')),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _danger),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(copy.text('Delete', 'Usuń')),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || _busy || _changingCover) return;
    setState(() => _busy = true);
    try {
      await service.deleteClub(club.id);
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            copy.isPolish
                ? 'Nie udało się usunąć klubu. Spróbuj ponownie za chwilę.'
                : intentionalOrFriendly(
                    error,
                    fallback:
                        "The Club couldn't be deleted. Please try again in a moment.",
                  ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final content = Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: Colors.white,
        title: Text(
          copy.text('Room settings', 'Ustawienia pokoju'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          TextButton(
            onPressed: _busy || _changingCover ? null : _save,
            child: Text(
              copy.text('SAVE', 'ZAPISZ'),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
      body: ResponsiveContentFrame(
        width: ResponsiveContentWidth.form,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 80),
            children: [
              _Section(
                title: copy.text('Room cover', 'Okładka pokoju'),
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: AspectRatio(
                      aspectRatio: 21 / 9,
                      child: _imageUrl?.trim().isNotEmpty == true
                          ? Image.network(
                              _imageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const _CoverFallback(),
                            )
                          : const _CoverFallback(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (widget.room.isActive)
                    OutlinedButton.icon(
                      onPressed: _changingCover || _busy ? null : _changeCover,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFF3A2C49)),
                        minimumSize: const Size.fromHeight(46),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: _changingCover
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.image_rounded, size: 18),
                      label: Text(
                        _changingCover
                            ? copy.text(
                                'Updating cover…',
                                'Aktualizowanie okładki…',
                              )
                            : _imageUrl?.trim().isNotEmpty == true
                            ? copy.text('Change cover', 'Zmień okładkę')
                            : copy.text('Add cover', 'Dodaj okładkę'),
                      ),
                    )
                  else if (widget.room.status == RoomStatus.suspended)
                    _CoverStatusNotice(
                      icon: Icons.gavel_rounded,
                      message: copy.text(
                        'This room is suspended by moderation. Its cover '
                            "can't be changed until the suspension is lifted.",
                        'Ten pokój został zawieszony przez moderację. Okładkę będzie można zmienić po cofnięciu zawieszenia.',
                      ),
                    )
                  else
                    _CoverStatusNotice(
                      icon: Icons.lock_open_rounded,
                      message: copy.text(
                        'Reopen this room to edit its cover.',
                        'Otwórz pokój ponownie, aby edytować okładkę.',
                      ),
                      actionLabel: copy.text('Reopen room', 'Otwórz pokój'),
                      onAction: _busy || _changingCover
                          ? null
                          : () => _setStatus(RoomStatus.active),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    copy.text(
                      'The cover becomes the room card on Home and Discover '
                          'and the stage backdrop inside the room.',
                      'Okładka pojawi się na karcie pokoju na stronie głównej i w sekcji Odkrywaj oraz jako tło sceny.',
                    ),
                    style: const TextStyle(
                      color: Color(0xFF9E92A8),
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
              _Section(
                title: copy.text('General', 'Ogólne'),
                children: [
                  _TextField(
                    controller: _name,
                    label: copy.text('Room name', 'Nazwa pokoju'),
                    maxLength: 50,
                    validator: (value) => (value?.trim().length ?? 0) < 3
                        ? copy.text(
                            'Enter at least 3 characters',
                            'Wpisz co najmniej 3 znaki',
                          )
                        : null,
                  ),
                  _TextField(
                    controller: _description,
                    label: copy.text('Description', 'Opis'),
                    maxLength: 160,
                    maxLines: 4,
                  ),
                  _Dropdown(
                    label: copy.text('Category', 'Kategoria'),
                    value: _category,
                    values: const [
                      'talk',
                      'music',
                      'gaming',
                      'chill',
                      'study',
                      'business',
                    ],
                    onChanged: (value) => setState(() => _category = value),
                  ),
                  _Dropdown(
                    label: copy.text('Language', 'Język'),
                    value: _language,
                    values: const [
                      'English',
                      'Polish',
                      'Dutch',
                      'German',
                      'French',
                      'Spanish',
                      'Italian',
                    ],
                    onChanged: (value) => setState(() => _language = value),
                  ),
                ],
              ),
              _Section(
                title: copy.text('Privacy', 'Prywatność'),
                children: [
                  _Dropdown(
                    label: copy.text('Visibility', 'Widoczność'),
                    value: _visibility,
                    values: const ['public', 'private'],
                    onChanged: (value) => setState(() => _visibility = value),
                  ),
                  SwitchListTile.adaptive(
                    value: _approvalRequired,
                    onChanged: (value) =>
                        setState(() => _approvalRequired = value),
                    title: Text(
                      copy.text(
                        'Require approval to join',
                        'Wymagaj akceptacji przed dołączeniem',
                      ),
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      copy.text(
                        'New members need owner approval.',
                        'Nowi członkowie wymagają zgody właściciela.',
                      ),
                      style: const TextStyle(color: _muted),
                    ),
                    activeTrackColor: _primary,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
              _Section(
                title: copy.text('Voice', 'Głos'),
                children: [
                  _Dropdown(
                    label: copy.text(
                      'Voice capacity',
                      'Limit uczestników rozmowy',
                    ),
                    value: _maxParticipants?.toString() ?? 'Unlimited',
                    values: const ['10', '25', '50', '100', 'Unlimited'],
                    onChanged: (value) => setState(() {
                      _maxParticipants = value == 'Unlimited'
                          ? null
                          : int.parse(value);
                    }),
                  ),
                  SwitchListTile.adaptive(
                    value: _autoMuteNewUsers,
                    onChanged: (value) =>
                        setState(() => _autoMuteNewUsers = value),
                    title: Text(
                      copy.text(
                        'Auto-mute new listeners',
                        'Automatycznie wyciszaj nowych słuchaczy',
                      ),
                      style: const TextStyle(color: Colors.white),
                    ),
                    activeTrackColor: _primary,
                    contentPadding: EdgeInsets.zero,
                  ),
                  SwitchListTile.adaptive(
                    value: _membersCanStartVoice,
                    onChanged: (value) =>
                        setState(() => _membersCanStartVoice = value),
                    title: Text(
                      copy.text(
                        'Members can start voice',
                        'Członkowie mogą rozpoczynać rozmowę',
                      ),
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      copy.text(
                        'Otherwise only the owner can start a session.',
                        'W przeciwnym razie sesję może uruchomić tylko właściciel.',
                      ),
                      style: const TextStyle(color: _muted),
                    ),
                    activeTrackColor: _primary,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
              _Section(
                title: copy.text('Chat', 'Czat'),
                children: [
                  _Dropdown(
                    label: copy.text('Slow mode', 'Tryb spowolniony'),
                    value: '$_slowModeSeconds',
                    values: const ['0', '5', '10', '30', '60'],
                    labels: {
                      '0': copy.text('Off', 'Wyłączony'),
                      '5': copy.text('5 seconds', '5 sekund'),
                      '10': copy.text('10 seconds', '10 sekund'),
                      '30': copy.text('30 seconds', '30 sekund'),
                      '60': copy.text('1 minute', '1 minuta'),
                    },
                    onChanged: (value) =>
                        setState(() => _slowModeSeconds = int.parse(value)),
                  ),
                ],
              ),
              _Section(
                title: copy.text('Room status', 'Status pokoju'),
                children: [
                  if (widget.room.isClosed || widget.room.isArchived)
                    _ActionTile(
                      icon: Icons.lock_open_rounded,
                      title: copy.text('Open room', 'Otwórz pokój'),
                      subtitle: copy.text(
                        'Make this room available again.',
                        'Ponownie udostępnij ten pokój.',
                      ),
                      onTap: _busy || _changingCover
                          ? null
                          : () => _setStatus(RoomStatus.active),
                    ),
                  if (widget.room.status != RoomStatus.suspended &&
                      !widget.room.isClosed)
                    _ActionTile(
                      icon: Icons.lock_rounded,
                      title: copy.text('Close room', 'Zamknij pokój'),
                      subtitle: copy.text(
                        'Pause access without deleting anything.',
                        'Wstrzymaj dostęp bez usuwania danych.',
                      ),
                      onTap: _busy || _changingCover
                          ? null
                          : () => _setStatus(RoomStatus.closed),
                    ),
                  if (widget.room.status != RoomStatus.suspended &&
                      !widget.room.isArchived)
                    _ActionTile(
                      icon: Icons.archive_rounded,
                      title: copy.text('Archive room', 'Zarchiwizuj pokój'),
                      subtitle: copy.text(
                        'Hide it from Discover and keep all data.',
                        'Ukryj go w sekcji Odkrywaj i zachowaj wszystkie dane.',
                      ),
                      onTap: _busy || _changingCover
                          ? null
                          : () => _setStatus(RoomStatus.archived),
                    ),
                  if (widget.room.storedClubId == null)
                    _ActionTile(
                      icon: Icons.delete_forever_rounded,
                      title: copy.text('Delete room', 'Usuń pokój'),
                      subtitle: copy.text(
                        'Permanently delete the room and its data.',
                        'Trwale usuń pokój i jego dane.',
                      ),
                      danger: true,
                      onTap: _busy || _changingCover ? null : _delete,
                    )
                  else if (_clubStream != null)
                    // A club lounge is deleted only by deleting its Club,
                    // and only its owner may do that. Ownership comes from
                    // the club DOCUMENT (Club.ownerId), never the room's
                    // possibly-stale hostId; while it is loading, errored
                    // or belongs to someone else there is no delete control
                    // at all — mirroring how a non-host sees an ordinary
                    // room.
                    StreamBuilder<Club>(
                      stream: _clubStream,
                      builder: (context, snapshot) {
                        final club = snapshot.data;
                        final uid = _clubService?.currentUserId ?? '';
                        if (club == null ||
                            uid.isEmpty ||
                            club.ownerId != uid) {
                          return const SizedBox.shrink();
                        }
                        return _ActionTile(
                          icon: Icons.delete_forever_rounded,
                          title: copy.text('Delete club', 'Usuń klub'),
                          subtitle: copy.text(
                            'Permanently delete the whole Club — its '
                                'lounge, chat, channels, members and invites.',
                            'Trwale usuń cały klub — jego pokój głosowy, czat, kanały, członków i zaproszenia.',
                          ),
                          danger: true,
                          onTap: _busy || _changingCover
                              ? null
                              : () => _deleteClub(club),
                        );
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return YoImmersiveDarkSurface(child: content);
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: _muted,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          Material(
            color: _surface,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: const BorderSide(color: _border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: children),
            ),
          ),
        ],
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  const _TextField({
    required this.controller,
    required this.label,
    this.maxLength,
    this.maxLines = 1,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final int? maxLength;
  final int maxLines;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        maxLength: maxLength,
        maxLines: maxLines,
        validator: validator,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: _muted),
          counterStyle: const TextStyle(color: _muted),
          enabledBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: _border),
          ),
          focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: _primary),
          ),
        ),
      ),
    );
  }
}

class _Dropdown extends StatelessWidget {
  const _Dropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
    this.labels = const {},
  });

  final String label;
  final String value;
  final List<String> values;
  final ValueChanged<String> onChanged;
  final Map<String, String> labels;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        dropdownColor: _surface,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: _muted),
          enabledBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: _border),
          ),
          focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: _primary),
          ),
        ),
        items: values
            .map(
              (item) => DropdownMenuItem(
                value: item,
                child: Text(
                  labels[item] ?? _localizedSettingOption(item, copy),
                ),
              ),
            )
            .toList(growable: false),
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
    );
  }
}

String _localizedSettingOption(String value, AppLocalizations copy) {
  if (!copy.isPolish) return value;
  return switch (value) {
    'talk' => 'Rozmowy',
    'music' => 'Muzyka',
    'gaming' => 'Gry',
    'chill' => 'Na luzie',
    'study' => 'Nauka',
    'business' => 'Biznes',
    'public' => 'Publiczny',
    'private' => 'Prywatny',
    'English' => 'Angielski',
    'Polish' => 'Polski',
    'Dutch' => 'Niderlandzki',
    'German' => 'Niemiecki',
    'French' => 'Francuski',
    'Spanish' => 'Hiszpański',
    'Italian' => 'Włoski',
    'Unlimited' => 'Bez limitu',
    _ => value,
  };
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final actionColor = danger ? _danger : _primary;
    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        enabled: enabled,
        leading: Icon(icon, color: enabled ? actionColor : _muted),
        title: Text(
          title,
          style: TextStyle(
            color: enabled ? (danger ? _danger : Colors.white) : _muted,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(subtitle, style: const TextStyle(color: _muted)),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: enabled ? _muted : _muted.withValues(alpha: .45),
        ),
        onTap: onTap,
      ),
    );
  }
}

class _CoverStatusNotice extends StatelessWidget {
  const _CoverStatusNotice({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF100C19),
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: _muted),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(color: _muted, height: 1.35),
                  ),
                ),
              ],
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 2),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.lock_open_rounded, size: 18),
                  label: Text(actionLabel!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Typed placeholder shown when the room has no cover yet.
class _CoverFallback extends StatelessWidget {
  const _CoverFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3A1657), Color(0xFF150F20)],
        ),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.image_outlined,
        size: 38,
        color: Colors.white.withValues(alpha: .25),
      ),
    );
  }
}
