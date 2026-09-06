import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/presentation/screens/room_entry_screen.dart';

/// Resolves the room behind a link. Null means "show nothing": the room is
/// gone, closed, or this account may not read it.
typedef RoomLinkResolver = Future<VoiceRoom?> Function(String roomId);

/// Opens a resolved room. The production default pushes [RoomEntryScreen],
/// the one consent boundary every room route goes through.
typedef RoomLinkOpener = void Function(BuildContext context, VoiceRoom room);

/// Reads are memoised for a short while so a chat list scrolling the same
/// invitation in and out of view does not re-fetch the document each time.
/// Failures are memoised too — a deleted room must not be retried on every
/// rebuild.
const Duration _roomLinkCacheLifetime = Duration(seconds: 45);
final Map<String, ({DateTime at, Future<VoiceRoom?> future})> _roomLinkCache =
    <String, ({DateTime at, Future<VoiceRoom?> future})>{};
RoomService? _roomLinkService;

/// The production resolver: one Firestore read through [RoomService.getRoom],
/// fail-closed. A private room the reader is not a member of surfaces as
/// permission-denied and therefore as null — the card simply does not
/// appear, and the plain text link above it still does.
Future<VoiceRoom?> defaultRoomLinkResolver(String roomId) {
  final now = DateTime.now();
  final cached = _roomLinkCache[roomId];
  if (cached != null && now.difference(cached.at) < _roomLinkCacheLifetime) {
    return cached.future;
  }
  final future = () async {
    try {
      final room = await (_roomLinkService ??= RoomService()).getRoom(roomId);
      return room.isActive ? room : null;
    } catch (_) {
      return null;
    }
  }();
  _roomLinkCache[roomId] = (at: now, future: future);
  return future;
}

/// Mirrors `NotificationRouter._openRoom`: the entry screen is the single
/// place that asks for consent before writing a roster row or touching
/// LiveKit, for links exactly as for pushes.
void defaultRoomLinkOpener(BuildContext context, VoiceRoom room) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => RoomEntryScreen(room: room)));
}

/// Clears the memoised reads and, optionally, installs the [RoomService]
/// the default resolver should read through — tests hand it a fake
/// Firestore; production leaves it null and gets the live one.
@visibleForTesting
void resetRoomLinkCache({RoomService? service}) {
  _roomLinkCache.clear();
  _roomLinkService = service;
}

/// A compact room card rendered under a text message that carries a room
/// link: type icon, room name, host, and a Join button. Renders nothing at
/// all when the room cannot be resolved.
class RoomLinkMessageCard extends StatefulWidget {
  const RoomLinkMessageCard({
    required this.roomId,
    required this.onBrandSurface,
    this.resolver,
    this.opener,
    super.key,
  });

  final String roomId;

  /// True inside an outgoing bubble (brand gradient, white copy); false on a
  /// themed incoming surface.
  final bool onBrandSurface;

  final RoomLinkResolver? resolver;
  final RoomLinkOpener? opener;

  @override
  State<RoomLinkMessageCard> createState() => _RoomLinkMessageCardState();
}

class _RoomLinkMessageCardState extends State<RoomLinkMessageCard> {
  late Future<VoiceRoom?> _room = _resolve();

  Future<VoiceRoom?> _resolve() =>
      (widget.resolver ?? defaultRoomLinkResolver)(widget.roomId);

  @override
  void didUpdateWidget(RoomLinkMessageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomId != widget.roomId) _room = _resolve();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<VoiceRoom?>(
      future: _room,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _RoomLinkLoading(onBrandSurface: widget.onBrandSurface);
        }
        final room = snapshot.data;
        if (room == null) return const SizedBox.shrink();
        return _RoomLinkCard(
          room: room,
          onBrandSurface: widget.onBrandSurface,
          onJoin: () => (widget.opener ?? defaultRoomLinkOpener)(context, room),
        );
      },
    );
  }
}

class _RoomLinkLoading extends StatelessWidget {
  const _RoomLinkLoading({required this.onBrandSurface});

  final bool onBrandSurface;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final muted = onBrandSurface ? Colors.white70 : palette.textSecondary;
    final copy = AppLocalizations.of(context);
    return Padding(
      key: const ValueKey('room-link-card-loading'),
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 12,
            child: CircularProgressIndicator(strokeWidth: 1.6, color: muted),
          ),
          const SizedBox(width: 8),
          Text(
            copy.text('Loading room…', 'Wczytywanie pokoju…'),
            style: TextStyle(color: muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _RoomLinkCard extends StatelessWidget {
  const _RoomLinkCard({
    required this.room,
    required this.onBrandSurface,
    required this.onJoin,
  });

  final VoiceRoom room;
  final bool onBrandSurface;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);
    final foreground = onBrandSurface ? Colors.white : palette.textPrimary;
    final muted = onBrandSurface ? Colors.white70 : palette.textSecondary;
    final surface = onBrandSurface
        ? Colors.white.withValues(alpha: .14)
        : palette.surfaceMuted;
    final border = onBrandSurface
        ? Colors.white.withValues(alpha: .22)
        : palette.border;
    final typeLabel = room.isBroadcast
        ? copy.text('Podcast', 'Podcast')
        : copy.text('Community room', 'Pokój społeczności');
    final host = room.hostName.trim();
    final hostLine = host.isEmpty
        ? typeLabel
        : copy.template(
            '{type} · hosted by {host}',
            '{type} · prowadzi {host}',
            values: <String, Object>{'type': typeLabel, 'host': host},
          );
    final joinLabel = room.isBroadcast
        ? copy.text('Join podcast', 'Dołącz do podcastu')
        : copy.text('Join room', 'Dołącz do pokoju');

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 220, maxWidth: 340),
        child: Container(
          key: const ValueKey('room-link-card'),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: onBrandSurface
                          ? Colors.white.withValues(alpha: .16)
                          : colors.primary.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      room.isBroadcast
                          ? Icons.podcasts_rounded
                          : Icons.groups_rounded,
                      size: 20,
                      color: onBrandSurface ? Colors.white : colors.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          room.name,
                          key: const ValueKey('room-link-card-name'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: foreground,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hostLine,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const ValueKey('room-link-card-join'),
                  onPressed: onJoin,
                  style: onBrandSurface
                      ? FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF7821E8),
                          visualDensity: VisualDensity.compact,
                        )
                      : FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                  icon: Icon(
                    room.isLive
                        ? Icons.graphic_eq_rounded
                        : Icons.login_rounded,
                    size: 18,
                  ),
                  label: Text(joinLabel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
