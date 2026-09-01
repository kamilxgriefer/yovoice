import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/features/moderation/data/models/moderation_audit_event.dart';
import 'package:yovoice/features/moderation/data/services/moderation_service.dart';

/// "Moderation history" for one report.
///
/// Reads through [ModerationService.reportAuditTrail], which calls the
/// scoped `listReportAuditTrail` callable — `adminAuditLogs` is denied
/// to every client, and that callable derives its target ids from the
/// report document, so nothing here can reach another report's history
/// or an unrelated admin action.
///
/// Two kinds of event are shown, and never merged: how the REPORT moved
/// (claimed, released, resolved, dismissed) and what happened to the
/// MESSAGE (removed, with the text as it was). A remove-and-resolve
/// legitimately produces one of each.
class ReportAuditTimeline extends StatefulWidget {
  const ReportAuditTimeline({
    required this.reportId,
    required this.service,
    required this.onAccessExpired,
    this.refreshToken = 0,
    super.key,
  });

  final String reportId;
  final ModerationService service;

  /// Raised when the trail comes back as access-expired, so the whole
  /// panel can clear itself rather than leaving report data on screen.
  final VoidCallback onAccessExpired;

  /// Bumped by the detail panel after a successful moderation action.
  /// The trail reloads from the first page — it never appends an event
  /// the server has not confirmed, and reloading rather than inserting
  /// is what stops the new event appearing twice.
  final int refreshToken;

  @override
  State<ReportAuditTimeline> createState() => _ReportAuditTimelineState();
}

class _ReportAuditTimelineState extends State<ReportAuditTimeline> {
  final List<ModerationAuditEvent> _events = <ModerationAuditEvent>[];
  final Set<String> _seen = <String>{};

  bool _loading = true;
  bool _loadingMore = false;

  /// Set when the trail comes back denied. Terminal for this widget —
  /// nothing is rendered and nothing is re-fetched until the panel
  /// rebuilds it.
  bool _revoked = false;
  bool _hasMore = false;
  String? _cursor;
  String? _error;

  /// Guards against a response for a PREVIOUS report (or a previous
  /// refresh) landing after the selection changed and repainting stale
  /// history under a different report's header.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(ReportAuditTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reportId != widget.reportId ||
        oldWidget.refreshToken != widget.refreshToken) {
      _reload();
    }
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    setState(() {
      _revoked = false;
      _events.clear();
      _seen.clear();
      _cursor = null;
      _hasMore = false;
      _error = null;
      _loading = true;
    });
    await _fetch(generation, append: false);
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() {
      _loadingMore = true;
      _error = null;
    });
    await _fetch(_generation, append: true);
  }

  Future<void> _fetch(int generation, {required bool append}) async {
    try {
      final page = await widget.service.reportAuditTrail(
        widget.reportId,
        cursor: append ? _cursor : null,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        for (final event in page.events) {
          // The cursor is a strict upper bound, so pages cannot overlap
          // — this is belt and braces against a duplicate ever
          // reaching the rendered list.
          if (_seen.add(event.id)) _events.add(event);
        }
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } on ModerationException catch (error) {
      if (!mounted || generation != _generation) return;
      if (error.failure == ModerationFailure.accessExpired) {
        // Drop what is already loaded before handing off, and go quiet:
        // the panel above is about to replace itself with the staff-only
        // notice, and until it does there must be neither history on
        // screen nor a spinner implying more is coming.
        setState(() {
          _events.clear();
          _seen.clear();
          _revoked = true;
          _loading = false;
          _loadingMore = false;
        });
        widget.onAccessExpired();
        return;
      }
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_revoked) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Moderation history',
              style: TextStyle(
                color: Color(0xFF9A90AC),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            if (!_loading && _error == null)
              Semantics(
                button: true,
                label: 'Refresh moderation history',
                child: IconButton(
                  onPressed: _reload,
                  tooltip: 'Refresh',
                  visualDensity: VisualDensity.compact,
                  iconSize: 15,
                  color: const Color(0xFF9A90AC),
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (_error != null && _events.isEmpty)
          _AuditProblem(message: _error!, onRetry: _reload)
        else if (_events.isEmpty)
          const Text(
            'No recorded activity yet.',
            style: TextStyle(color: Color(0xFF7E7895), fontSize: 12),
          )
        else ...[
          for (final event in _events)
            _AuditRow(key: ValueKey(event.id), event: event),
          // A failure while paging keeps the history already on screen —
          // losing it would be a worse answer than the one page that did
          // not arrive. Retrying resumes from the same cursor.
          if (_error != null)
            _AuditProblem(message: _error!, onRetry: _loadMore),
          if (_hasMore && _error == null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _loadingMore ? null : _loadMore,
                child: Text(
                  _loadingMore ? 'Loading…' : 'Load earlier activity',
                  style: TextStyle(
                    color: _loadingMore
                        ? const Color(0xFF564C63)
                        : const Color(0xFFD3A5FF),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _AuditProblem extends StatelessWidget {
  const _AuditProblem({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: AppColors.warning.withValues(alpha: .08),
        border: Border.all(color: AppColors.warning.withValues(alpha: .3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFCFC6DC),
                fontSize: 11.5,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            button: true,
            label: 'Retry loading moderation history',
            child: TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Retry',
                style: TextStyle(
                  color: Color(0xFFD3A5FF),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuditRow extends StatelessWidget {
  const _AuditRow({required this.event, super.key});

  final ModerationAuditEvent event;

  static String actionLabel(ModerationAuditEvent event) {
    if (event.kind == ModerationAuditKind.contentModeration) {
      return 'Message removed';
    }
    return switch (event.action) {
      'report_claim' => 'Claimed for review',
      'report_release' => 'Claim released',
      'report_resolve' => 'Resolved',
      'report_removeAndResolve' => 'Removed content and resolved',
      'report_dismiss' => 'Dismissed',
      _ => 'Recorded action',
    };
  }

  static String stamp(DateTime? at) {
    if (at == null) return '';
    return at.toString().split('.').first;
  }

  @override
  Widget build(BuildContext context) {
    final isContent = event.kind == ModerationAuditKind.contentModeration;
    final accent = isContent
        ? const Color(0xFFFF7A93)
        : const Color(0xFF5CE1E6);

    return Semantics(
      label:
          '${actionLabel(event)}'
          '${event.actorName == null ? '' : ' by ${event.actorName}'}, '
          '${stamp(event.createdAt)}',
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.white.withValues(alpha: .02),
          border: Border.all(color: const Color(0xFF241A33)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    actionLabel(event),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                // Which question this row answers, spelled out so the
                // two record types are never mistaken for one another.
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: accent.withValues(alpha: .12),
                    border: Border.all(color: accent.withValues(alpha: .35)),
                  ),
                  child: Text(
                    isContent ? 'Content' : 'Report',
                    style: TextStyle(
                      color: accent,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [
                if (event.actorName != null)
                  event.actorName!
                else if (event.actorId != null)
                  event.actorId!,
                if (event.actorRole != null) '(${event.actorRole})',
                stamp(event.createdAt),
              ].join(' · '),
              style: const TextStyle(color: Color(0xFF7E7895), fontSize: 10.5),
            ),
            if (event.previousStatus != null && event.newStatus != null) ...[
              const SizedBox(height: 4),
              Text(
                // '›' rather than '→': Roboto is what CanvasKit falls
                // back to on web and it has no U+2192, so the arrow
                // rendered as a tofu box. Caught by looking at it.
                '${event.previousStatus} › ${event.newStatus}'
                '${event.resolution == null ? '' : ' · ${event.resolution}'}'
                '${event.contentRemoved ? ' · content removed' : ''}',
                style: const TextStyle(color: Color(0xFFB3A8C4), fontSize: 11),
              ),
            ],
            if (event.note != null) ...[
              const SizedBox(height: 4),
              Text(
                event.note!,
                style: const TextStyle(
                  color: Color(0xFFCFC6DC),
                  fontSize: 11.5,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            if (event.removedContent != null) ...[
              const SizedBox(height: 5),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  color: Colors.black.withValues(alpha: .25),
                ),
                child: SelectableText(
                  event.removedContent!,
                  style: const TextStyle(
                    color: Color(0xFF9A90AC),
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
              ),
            ],
            if (event.kind == ModerationAuditKind.unknown) ...[
              const SizedBox(height: 4),
              const Text(
                'This entry has a shape this version does not recognise.',
                style: TextStyle(color: Color(0xFF7E7895), fontSize: 10.5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
