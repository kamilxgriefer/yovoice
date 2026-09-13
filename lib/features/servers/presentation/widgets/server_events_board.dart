import 'package:flutter/material.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_typography.dart';

import '../../data/models/server.dart';
import '../../data/models/server_channel.dart';
import '../../data/models/server_event.dart';
import '../../data/models/server_member_role.dart';
import '../../data/models/server_type.dart';
import '../../data/services/server_service.dart';
import '../server_action_failure.dart';
import '../server_localized_copy.dart';
import '../theme/server_identity.dart';

class ServerEventsBoard extends StatefulWidget {
  const ServerEventsBoard({
    required this.server,
    required this.channel,
    required this.repository,
    required this.role,
    required this.currentUserId,
    this.now,
    super.key,
  });

  final Server server;
  final ServerChannel channel;
  final ServerRepository repository;
  final ServerMemberRole? role;
  final String currentUserId;
  final DateTime Function()? now;

  @override
  State<ServerEventsBoard> createState() => _ServerEventsBoardState();
}

class _ServerEventsBoardState extends State<ServerEventsBoard> {
  String? _busyEventId;
  String? _feedback;
  bool _feedbackIsError = false;

  DateTime get _now => (widget.now?.call() ?? DateTime.now()).toUtc();

  ServerEventsRepository? get _events =>
      widget.repository is ServerEventsRepository
      ? widget.repository as ServerEventsRepository
      : null;

  Future<void> _run(
    String eventId,
    Future<void> Function() action, {
    required String success,
  }) async {
    if (_busyEventId != null) return;
    setState(() {
      _busyEventId = eventId;
      _feedback = null;
      _feedbackIsError = false;
    });
    try {
      await action();
      if (mounted) {
        setState(() {
          _busyEventId = null;
          _feedback = success;
          _feedbackIsError = false;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busyEventId = null;
        _feedback = serverActionFailureCopy(
          error,
          AppLocalizations.of(context),
        );
        _feedbackIsError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final service = _events;
    final colors = ServerIdentity.of(
      widget.server.type,
    ).resolve(Theme.of(context).brightness);
    if (service == null) {
      return Center(child: Text(copy.serverActionUnavailable));
    }
    final canCreate =
        widget.role != null &&
        widget.role != ServerMemberRole.guest &&
        !widget.server.isHeld;
    return Material(
      color: Colors.transparent,
      child: StreamBuilder<List<ServerEvent>>(
        stream: service.watchEvents(widget.server.id, widget.channel.id),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  serverActionFailureCopy(snapshot.error!, copy),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final events =
              snapshot.data!
                  .where(
                    (event) =>
                        event.status == ServerEventStatus.scheduled &&
                        event.endsAt.isAfter(_now),
                  )
                  .toList(growable: false)
                ..sort((first, second) {
                  final starts = first.startsAt.compareTo(second.startsAt);
                  return starts != 0 ? starts : first.id.compareTo(second.id);
                });
          return CustomScrollView(
            key: const ValueKey('server-events-board'),
            slivers: [
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: colors.cardWash,
                    borderRadius: AppRadius.xl,
                    border: Border.all(color: colors.iconBorder),
                  ),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 440,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              widget.server.type == ServerType.podcast
                                  ? Icons.podcasts_outlined
                                  : widget.server.type == ServerType.family
                                  ? Icons.calendar_month_outlined
                                  : Icons.event_available_outlined,
                              color: colors.foreground,
                              size: 30,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              copy.serverEventsTitle(widget.server.type),
                              style: AppTypography.headlineSmall.copyWith(
                                color: palette.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              copy.serverEventsBody(widget.server.type),
                              style: AppTypography.bodyMedium.copyWith(
                                color: palette.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (canCreate)
                        FilledButton.icon(
                          key: const ValueKey('server-create-event'),
                          onPressed: _busyEventId == null
                              ? () => _editEvent(context)
                              : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: colors.cta,
                            foregroundColor: colors.onCta,
                            minimumSize: const Size(180, 48),
                          ),
                          icon: const Icon(Icons.add_rounded),
                          label: Text(
                            copy.serverCreateEventFor(widget.server.type),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (_feedback != null)
                SliverToBoxAdapter(
                  child: Semantics(
                    key: const ValueKey('server-event-feedback'),
                    liveRegion: true,
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _feedbackIsError
                            ? palette.dangerSurface
                            : palette.successSurface,
                        borderRadius: AppRadius.md,
                      ),
                      child: Text(
                        _feedback!,
                        key: ValueKey(
                          _feedbackIsError
                              ? 'server-event-error'
                              : 'server-event-success',
                        ),
                        style: TextStyle(
                          color: _feedbackIsError
                              ? palette.dangerForeground
                              : palette.successForeground,
                        ),
                      ),
                    ),
                  ),
                ),
              if (events.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        copy.serverNoUpcomingEvents,
                        textAlign: TextAlign.center,
                        style: AppTypography.bodyMedium.copyWith(
                          color: palette.textSecondary,
                        ),
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                  sliver: SliverList.separated(
                    itemCount: events.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final event = events[index];
                      return _EventCard(
                        event: event,
                        response: service.watchMyEventResponse(
                          widget.server.id,
                          widget.channel.id,
                          event.id,
                        ),
                        canManage:
                            event.authorId == widget.currentUserId ||
                            (widget.role?.canModerate ?? false),
                        acceptsResponses: event.acceptsResponsesAt(_now),
                        busy: _busyEventId == event.id,
                        onRespond: (response, reminderRequested) => _run(
                          event.id,
                          () => service.respondToEvent(
                            event: event,
                            response: response,
                            reminderRequested: event.reminderOptInEnabled
                                ? reminderRequested
                                : null,
                            requestId: widget.repository.newRequestId(),
                          ),
                          success: copy.serverEventResponseSaved,
                        ),
                        onReminder: (attendance, enabled) => _run(
                          event.id,
                          () => service.respondToEvent(
                            event: event,
                            response: attendance.response,
                            reminderRequested: enabled,
                            requestId: widget.repository.newRequestId(),
                          ),
                          success: copy.serverEventReminderSaved,
                        ),
                        onEdit: () => _editEvent(context, event),
                        onCancel: () => _cancel(context, event),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _editEvent(BuildContext context, [ServerEvent? event]) async {
    final copy = AppLocalizations.of(context);
    final draft = await showDialog<_EventDraft>(
      context: context,
      builder: (_) => _EventEditorDialog(event: event, now: _now),
    );
    final service = _events;
    if (!mounted || draft == null || service == null) return;
    await _run(
      event?.id ?? 'create',
      () => event == null
          ? service.createEvent(
              serverId: widget.server.id,
              channelId: widget.channel.id,
              title: draft.title,
              description: draft.description,
              startsAt: draft.startsAt,
              endsAt: draft.endsAt,
              timeZone: draft.timeZone,
              requestId: widget.repository.newRequestId(),
            )
          : service.updateEvent(
              event: event,
              title: draft.title,
              description: draft.description,
              startsAt: draft.startsAt,
              endsAt: draft.endsAt,
              timeZone: draft.timeZone,
              requestId: widget.repository.newRequestId(),
            ),
      success: event == null
          ? copy.serverEventCreated
          : copy.serverEventUpdated,
    );
  }

  Future<void> _cancel(BuildContext context, ServerEvent event) async {
    final copy = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text(copy.serverCancelEventQuestion),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(copy.serverCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(copy.serverCancelEvent),
          ),
        ],
      ),
    );
    final service = _events;
    if (!mounted || confirmed != true || service == null) return;
    await _run(
      event.id,
      () => service.cancelEvent(
        event: event,
        requestId: widget.repository.newRequestId(),
      ),
      success: copy.serverEventCancelled,
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.response,
    required this.canManage,
    required this.acceptsResponses,
    required this.busy,
    required this.onRespond,
    required this.onReminder,
    required this.onEdit,
    required this.onCancel,
  });

  final ServerEvent event;
  final Stream<ServerEventAttendance?> response;
  final bool canManage;
  final bool acceptsResponses;
  final bool busy;
  final void Function(ServerEventResponse response, bool reminderRequested)
  onRespond;
  final void Function(ServerEventAttendance attendance, bool enabled)
  onReminder;
  final VoidCallback onEdit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final zoned = ServerEventTime.inZone(event.startsAt, event.timeZone);
    final date = MaterialLocalizations.of(context).formatMediumDate(zoned);
    final time = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(zoned));
    return Container(
      key: ValueKey('server-event-${event.id}'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadius.lg,
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: palette.surfaceMuted,
                  borderRadius: AppRadius.md,
                ),
                child: Column(
                  children: [
                    Text(
                      '${zoned.day}',
                      style: AppTypography.titleMedium.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                    Text(
                      time,
                      style: AppTypography.labelSmall.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      style: AppTypography.titleMedium.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$date · $time · ${event.timeZone}',
                      style: AppTypography.bodySmall.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (canManage)
                PopupMenuButton<_EventAction>(
                  enabled: !busy,
                  tooltip: copy.text('Event actions', 'Działania wydarzenia'),
                  onSelected: (action) => switch (action) {
                    _EventAction.edit => onEdit(),
                    _EventAction.cancel => onCancel(),
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: _EventAction.edit,
                      child: Text(copy.serverEditEvent),
                    ),
                    PopupMenuItem(
                      value: _EventAction.cancel,
                      child: Text(copy.serverCancelEvent),
                    ),
                  ],
                ),
            ],
          ),
          if (event.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              event.description,
              style: AppTypography.bodyMedium.copyWith(
                color: palette.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 14),
          StreamBuilder<ServerEventAttendance?>(
            stream: response,
            builder: (context, snapshot) {
              final attendance = snapshot.data;
              final selected = attendance?.response;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _ResponseChip(
                        label: copy.serverEventGoing,
                        count: event.goingCount,
                        selected: selected == ServerEventResponse.going,
                        onTap: busy || !acceptsResponses
                            ? null
                            : () => onRespond(
                                ServerEventResponse.going,
                                attendance?.reminderRequested ?? false,
                              ),
                      ),
                      _ResponseChip(
                        label: copy.serverEventMaybe,
                        count: event.maybeCount,
                        selected: selected == ServerEventResponse.maybe,
                        onTap: busy || !acceptsResponses
                            ? null
                            : () => onRespond(
                                ServerEventResponse.maybe,
                                attendance?.reminderRequested ?? false,
                              ),
                      ),
                      _ResponseChip(
                        label: copy.serverEventDeclined,
                        count: event.declinedCount,
                        selected: selected == ServerEventResponse.declined,
                        onTap: busy || !acceptsResponses
                            ? null
                            : () => onRespond(
                                ServerEventResponse.declined,
                                attendance?.reminderRequested ?? false,
                              ),
                      ),
                    ],
                  ),
                  if (event.reminderOptInEnabled) ...[
                    const SizedBox(height: 8),
                    FilterChip(
                      key: ValueKey('server-event-reminder-${event.id}'),
                      avatar: const Icon(
                        Icons.notifications_none_rounded,
                        size: 18,
                      ),
                      label: Text(
                        '${copy.serverEventReminder} · ${event.reminderCount}',
                      ),
                      selected: attendance?.reminderRequested ?? false,
                      onSelected:
                          busy || !acceptsResponses || attendance == null
                          ? null
                          : (enabled) => onReminder(attendance, enabled),
                    ),
                  ],
                  if (!acceptsResponses) ...[
                    const SizedBox(height: 8),
                    Text(
                      copy.serverEventStarted,
                      key: ValueKey('server-event-closed-${event.id}'),
                      style: AppTypography.bodySmall.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
          if (busy) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(minHeight: 2),
          ],
        ],
      ),
    );
  }
}

class _ResponseChip extends StatelessWidget {
  const _ResponseChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => FilterChip(
    selected: selected,
    onSelected: onTap == null ? null : (_) => onTap!(),
    label: Text('$label · $count'),
  );
}

class _EventDraft {
  const _EventDraft({
    required this.title,
    required this.description,
    required this.startsAt,
    required this.endsAt,
    required this.timeZone,
  });

  final String title;
  final String description;
  final DateTime startsAt;
  final DateTime endsAt;
  final String timeZone;
}

class _EventEditorDialog extends StatefulWidget {
  const _EventEditorDialog({this.event, required this.now});
  final ServerEvent? event;
  final DateTime now;

  @override
  State<_EventEditorDialog> createState() => _EventEditorDialogState();
}

class _EventEditorDialogState extends State<_EventEditorDialog> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _timeZone;
  late DateTime _startsAt;
  late DateTime _endsAt;

  @override
  void initState() {
    super.initState();
    final zone = widget.event?.timeZone ?? 'UTC';
    final now = ServerEventTime.inZone(widget.now.toUtc(), zone);
    final defaultStart = now.add(const Duration(hours: 1));
    _startsAt = ServerEventTime.wallClock(
      widget.event == null
          ? DateTime.utc(
              defaultStart.year,
              defaultStart.month,
              defaultStart.day,
              defaultStart.hour,
            )
          : ServerEventTime.inZone(widget.event!.startsAt, zone),
    );
    _endsAt = ServerEventTime.wallClock(
      widget.event == null
          ? _startsAt.add(const Duration(hours: 1))
          : ServerEventTime.inZone(widget.event!.endsAt, zone),
    );
    _title = TextEditingController(text: widget.event?.title ?? '');
    _description = TextEditingController(text: widget.event?.description ?? '');
    _timeZone = TextEditingController(text: widget.event?.timeZone ?? 'UTC');
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _timeZone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final valid = _draft() != null;
    return AlertDialog(
      title: Text(
        widget.event == null ? copy.serverCreateEvent : copy.serverEditEvent,
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const ValueKey('server-event-title'),
                controller: _title,
                autofocus: true,
                maxLength: 120,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: copy.serverEventTitle),
              ),
              TextField(
                key: const ValueKey('server-event-description'),
                controller: _description,
                maxLength: 2000,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: copy.serverEventDescription,
                ),
              ),
              const SizedBox(height: 8),
              _DateTimeTile(
                label: copy.serverEventStarts,
                value: _startsAt,
                onTap: () => _pickDateTime(start: true),
              ),
              _DateTimeTile(
                label: copy.serverEventEnds,
                value: _endsAt,
                onTap: () => _pickDateTime(start: false),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('server-event-timezone'),
                controller: _timeZone,
                maxLength: 64,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: copy.serverEventTimeZone,
                  hintText: copy.serverEventTimeZoneHint,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(copy.serverCancel),
        ),
        FilledButton(
          key: const ValueKey('server-event-save'),
          onPressed: valid
              ? () {
                  final draft = _draft();
                  if (draft != null) Navigator.of(context).pop(draft);
                }
              : null,
          child: Text(
            widget.event == null
                ? copy.serverEventCreateAction
                : copy.serverEventUpdateAction,
          ),
        ),
      ],
    );
  }

  _EventDraft? _draft() {
    final title = _title.text.trim();
    final zone = _timeZone.text.trim();
    if (title.isEmpty || !ServerEventTime.isValidZone(zone)) return null;
    final startsAt = ServerEventTime.wallClockToUtc(_startsAt, zone);
    final endsAt = ServerEventTime.wallClockToUtc(_endsAt, zone);
    if (!startsAt.isAfter(DateTime.now().toUtc()) ||
        !endsAt.isAfter(startsAt)) {
      return null;
    }
    return _EventDraft(
      title: title,
      description: _description.text.trim(),
      startsAt: startsAt,
      endsAt: endsAt,
      timeZone: zone,
    );
  }

  Future<void> _pickDateTime({required bool start}) async {
    final current = start ? _startsAt : _endsAt;
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 732)),
    );
    if (!mounted || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (!mounted || time == null) return;
    final value = DateTime.utc(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() {
      if (start) {
        final duration = _endsAt.difference(_startsAt);
        _startsAt = value;
        _endsAt = value.add(
          duration.isNegative ? const Duration(hours: 1) : duration,
        );
      } else {
        _endsAt = value;
      }
    });
  }
}

class _DateTimeTile extends StatelessWidget {
  const _DateTimeTile({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final DateTime value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final formatted =
        '${localizations.formatMediumDate(value)} · '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(value))}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minTileHeight: 56,
      leading: const Icon(Icons.schedule_rounded),
      title: Text(label),
      subtitle: Text(formatted),
      onTap: onTap,
    );
  }
}

enum _EventAction { edit, cancel }
