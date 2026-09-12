import 'dart:async';

import 'package:flutter/material.dart';

import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_places_section.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';

/// Subscribes to the club lounges of the head memberships and hands the
/// result down as one map.
///
/// Bounded by construction: the caller passes at most [budget] clubs, so Home
/// can never fan out a listener per membership. A lounge that fails to read is
/// reported as failed rather than dropped — a place Home cannot check is not
/// a quiet place.
///
/// Shared by both Home compositions on purpose. The phone and the desktop
/// arrange these places very differently, but "which of my places is talking
/// right now" is one question with one answer, and answering it twice would
/// be two sets of Firestore listeners for the same fact.
class HomeLoungeWatcher extends StatefulWidget {
  const HomeLoungeWatcher({
    required this.clubs,
    required this.rooms,
    required this.generation,
    required this.builder,
    super.key,
  });

  /// How many memberships get a lounge listener. The rows either Home can
  /// show are capped at three, so a fourth listener is the most the hero can
  /// add.
  static const int budget = 4;

  final List<Club> clubs;
  final RoomService? rooms;

  /// Bumped by the places retry to force a fresh subscription.
  final int generation;
  final Widget Function(BuildContext context, Map<String, HomePlace> lounges)
  builder;

  @override
  State<HomeLoungeWatcher> createState() => _HomeLoungeWatcherState();
}

class _HomeLoungeWatcherState extends State<HomeLoungeWatcher> {
  final Map<String, StreamSubscription<VoiceRoom?>> _subscriptions = {};
  final Map<String, HomePlace> _places = {};

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant HomeLoungeWatcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sameOrder =
        oldWidget.clubs.length == widget.clubs.length &&
        List.generate(
          widget.clubs.length,
          (index) => oldWidget.clubs[index].id == widget.clubs[index].id,
        ).every((same) => same);
    if (!sameOrder ||
        oldWidget.rooms != widget.rooms ||
        oldWidget.generation != widget.generation) {
      if (oldWidget.generation != widget.generation ||
          oldWidget.rooms != widget.rooms) {
        _cancelAll();
      }
      _sync();
    } else {
      // Same clubs in the same order: refresh the club documents on the
      // existing rows without touching a single subscription.
      for (final club in widget.clubs) {
        final existing = _places[club.id];
        if (existing != null) {
          _places[club.id] = HomePlace(
            club: club,
            lounge: existing.lounge,
            loungeFailed: existing.loungeFailed,
            loungeLoading: existing.loungeLoading,
          );
        }
      }
    }
  }

  void _cancelAll() {
    for (final subscription in _subscriptions.values) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    _places.clear();
  }

  void _sync() {
    final wanted = widget.clubs.map((club) => club.id).toSet();
    for (final id in _subscriptions.keys.toList(growable: false)) {
      if (wanted.contains(id)) continue;
      unawaited(_subscriptions.remove(id)!.cancel());
      _places.remove(id);
    }
    final rooms = widget.rooms;
    for (final club in widget.clubs) {
      _places[club.id] =
          _places[club.id] ??
          HomePlace(club: club, loungeLoading: rooms != null);
      if (rooms == null || _subscriptions.containsKey(club.id)) continue;
      try {
        _subscriptions[club.id] = rooms
            .watchClubLounge(club.id)
            .listen(
              (lounge) => _publish(
                club.id,
                (place) => HomePlace(club: place.club, lounge: lounge),
              ),
              onError: (Object _) => _publish(
                club.id,
                (place) => HomePlace(club: place.club, loungeFailed: true),
              ),
            );
      } catch (_) {
        _places[club.id] = HomePlace(club: club, loungeFailed: true);
      }
    }
  }

  void _publish(String clubId, HomePlace Function(HomePlace) update) {
    if (!mounted) return;
    final existing = _places[clubId];
    if (existing == null) return;
    setState(() => _places[clubId] = update(existing));
  }

  @override
  void dispose() {
    _cancelAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, Map.unmodifiable(_places));
}
