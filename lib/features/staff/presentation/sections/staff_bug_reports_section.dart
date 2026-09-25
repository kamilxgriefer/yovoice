import 'dart:async';

import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/bug_reports/data/bug_report_admin_service.dart';
import 'package:yovoice/features/staff/presentation/sections/staff_section_shared.dart';

/// Staff Center > Bug reports: the owner's inbox for in-app bug reports.
///
/// Rendered only for the owner (`manageRoles`, which the server derives from
/// the YOVOICE_PROTECTED_OWNER_UID secret); the callables behind it refuse
/// everybody else regardless. Works with nothing else configured — the e-mail
/// and GitHub alerts are optional announcements of what is listed here.
///
/// Wide (>= 900 px of section width): list and detail side by side. Narrow:
/// the list, and a pushed detail page with its own Back.
class StaffBugReportsSection extends StatefulWidget {
  const StaffBugReportsSection({this.service, super.key});

  final BugReportAdminService? service;

  @override
  State<StaffBugReportsSection> createState() => _StaffBugReportsSectionState();
}

String bugReportStatusLabel(AppLocalizations copy, String status) =>
    switch (status) {
      'triaged' => copy.text('Triaged', 'W analizie'),
      'resolved' => copy.text('Resolved', 'Rozwiązane'),
      'dismissed' => copy.text('Dismissed', 'Odrzucone'),
      _ => copy.text('New', 'Nowe'),
    };

Color _statusColor(String status) => switch (status) {
  'triaged' => StaffCenterStyle.warn,
  'resolved' => StaffCenterStyle.good,
  'dismissed' => StaffCenterStyle.faint,
  _ => StaffCenterStyle.accent,
};

class _StaffBugReportsSectionState extends State<StaffBugReportsSection> {
  late final BugReportAdminService _service =
      widget.service ?? BugReportAdminService();

  String? _status;
  final List<BugReportSummary> _reports = <BugReportSummary>[];
  String? _nextCursor;
  bool _loading = true;
  bool _loadingMore = false;
  bool _failed = false;
  String? _selectedId;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final epoch = ++_epoch;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final page = await _service.list(status: _status);
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _reports
          ..clear()
          ..addAll(page.reports);
        _nextCursor = page.nextCursor;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _loadMore() async {
    final cursor = _nextCursor;
    if (cursor == null || _loadingMore) return;
    final epoch = _epoch;
    setState(() => _loadingMore = true);
    try {
      final page = await _service.list(status: _status, cursor: cursor);
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _reports.addAll(page.reports);
        _nextCursor = page.nextCursor;
      });
    } catch (_) {
      // The button stays; the next tap retries.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _filter(String? status) {
    if (_status == status) return;
    setState(() {
      _status = status;
      _selectedId = null;
    });
    unawaited(_load());
  }

  void _statusChanged(String reportId, String status) {
    final index = _reports.indexWhere((row) => row.reportId == reportId);
    if (index < 0) return;
    final row = _reports[index];
    setState(() {
      _reports[index] = BugReportSummary(
        reportId: row.reportId,
        reporterId: row.reporterId,
        status: status,
        createdAt: row.createdAt,
        descriptionPreview: row.descriptionPreview,
        platform: row.platform,
        appVersion: row.appVersion,
        buildNumber: row.buildNumber,
        route: row.route,
        screenshotStatus: row.screenshotStatus,
      );
    });
  }

  Future<void> _open(BugReportSummary row, {required bool wide}) async {
    if (wide) {
      setState(() => _selectedId = row.reportId);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) {
          final copy = AppLocalizations.of(routeContext);
          return Scaffold(
            backgroundColor: StaffCenterStyle.background,
            appBar: AppBar(
              backgroundColor: StaffCenterStyle.background,
              foregroundColor: Colors.white,
              title: Text(copy.text('Bug report', 'Zgłoszenie błędu')),
            ),
            body: BugReportDetailView(
              reportId: row.reportId,
              service: _service,
              onStatusChanged: (status) => _statusChanged(row.reportId, status),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final list = _list(copy, wide: wide);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StaffSectionHeader(
              title: copy.text('Bug reports', 'Zgłoszenia błędów'),
              subtitle: copy.text(
                'Reports sent from the app. Only you can read them; screenshots open for five minutes at a time.',
                'Zgłoszenia wysłane z aplikacji. Możesz je czytać tylko Ty; zrzuty ekranu otwierają się na pięć minut.',
              ),
              trailing: IconButton(
                tooltip: copy.text('Refresh', 'Odśwież'),
                onPressed: _loading ? null : () => unawaited(_load()),
                icon: const Icon(
                  Icons.refresh_rounded,
                  color: StaffCenterStyle.muted,
                ),
              ),
            ),
            _filters(copy),
            const SizedBox(height: 10),
            Expanded(
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: 380, child: list),
                        const SizedBox(width: 14),
                        Expanded(
                          child: StaffPanel(
                            child: _selectedId == null
                                ? StaffEmptyState(
                                    icon: Icons.bug_report_outlined,
                                    message: copy.text(
                                      'Choose a report to read it.',
                                      'Wybierz zgłoszenie, aby je przeczytać.',
                                    ),
                                  )
                                : BugReportDetailView(
                                    key: ValueKey(_selectedId),
                                    reportId: _selectedId!,
                                    service: _service,
                                    onStatusChanged: (status) =>
                                        _statusChanged(_selectedId!, status),
                                  ),
                          ),
                        ),
                      ],
                    )
                  : list,
            ),
          ],
        );
      },
    );
  }

  Widget _filters(AppLocalizations copy) {
    final options = <String?>[null, ...bugReportStatuses];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final option in options) ...[
            ChoiceChip(
              label: Text(
                option == null
                    ? copy.text('All', 'Wszystkie')
                    : bugReportStatusLabel(copy, option),
              ),
              selected: _status == option,
              onSelected: (_) => _filter(option),
              labelStyle: TextStyle(
                color: _status == option
                    ? Colors.white
                    : StaffCenterStyle.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              selectedColor: StaffCenterStyle.accent.withValues(alpha: .35),
              backgroundColor: StaffCenterStyle.surfaceRaised,
              side: const BorderSide(color: StaffCenterStyle.border),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  Widget _list(AppLocalizations copy, {required bool wide}) {
    if (_loading) {
      return Center(
        child: Semantics(
          label: copy.text('Loading bug reports', 'Wczytywanie zgłoszeń'),
          child: const CircularProgressIndicator(),
        ),
      );
    }
    if (_failed) {
      return StaffErrorState(
        message: copy.text(
          'Bug reports could not be loaded.',
          'Nie udało się wczytać zgłoszeń.',
        ),
        onRetry: () => unawaited(_load()),
      );
    }
    if (_reports.isEmpty) {
      return StaffEmptyState(
        icon: Icons.bug_report_outlined,
        message: copy.text('No bug reports here.', 'Brak zgłoszeń.'),
      );
    }
    return ListView.separated(
      key: const ValueKey('staff-bug-report-list'),
      itemCount: _reports.length + (_nextCursor == null ? 0 : 1),
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index >= _reports.length) {
          return Center(
            child: OutlinedButton(
              onPressed: _loadingMore ? null : () => unawaited(_loadMore()),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: StaffCenterStyle.border),
              ),
              child: Text(copy.text('Load more', 'Wczytaj więcej')),
            ),
          );
        }
        final row = _reports[index];
        return _BugReportRow(
          row: row,
          selected: wide && _selectedId == row.reportId,
          onTap: () => unawaited(_open(row, wide: wide)),
        );
      },
    );
  }
}

class _BugReportRow extends StatelessWidget {
  const _BugReportRow({
    required this.row,
    required this.selected,
    required this.onTap,
  });

  final BugReportSummary row;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final meta = [
      row.platform ?? '—',
      if (row.appVersion != null)
        '${row.appVersion}${row.buildNumber == null ? '' : '+${row.buildNumber}'}',
      row.route ?? '—',
      staffStamp(copy, row.createdAt),
    ].join(' · ');
    return Material(
      color: selected
          ? StaffCenterStyle.accent.withValues(alpha: .16)
          : StaffCenterStyle.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: ValueKey('staff-bug-report-${row.reportId}'),
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: StaffCenterStyle.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _StatusPill(status: row.status),
                  const Spacer(),
                  if (row.screenshotStatus == 'attached')
                    Icon(
                      Icons.image_outlined,
                      size: 16,
                      color: StaffCenterStyle.muted,
                      semanticLabel: copy.text(
                        'Has a screenshot',
                        'Ma zrzut ekranu',
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                row.descriptionPreview,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 13.5),
              ),
              const SizedBox(height: 6),
              Text(
                meta,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: StaffCenterStyle.faint,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .55)),
      ),
      child: Text(
        bugReportStatusLabel(copy, status),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// One report in full: the reporter's words, the device context, the
/// screenshot (a five-minute signed URL), alert delivery and the triage
/// status.
class BugReportDetailView extends StatefulWidget {
  const BugReportDetailView({
    required this.reportId,
    required this.service,
    this.onStatusChanged,
    super.key,
  });

  final String reportId;
  final BugReportAdminService service;
  final ValueChanged<String>? onStatusChanged;

  @override
  State<BugReportDetailView> createState() => _BugReportDetailViewState();
}

class _BugReportDetailViewState extends State<BugReportDetailView> {
  BugReportDetail? _detail;
  bool _failed = false;
  bool _saving = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final detail = await widget.service.get(widget.reportId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _status = detail.summary.status;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _setStatus(String status) async {
    final copy = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _saving = true);
    try {
      await widget.service.updateStatus(widget.reportId, status);
      if (!mounted) return;
      setState(() => _status = status);
      widget.onStatusChanged?.call(status);
    } catch (_) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            copy.text(
              'The status could not be saved.',
              'Nie udało się zapisać statusu.',
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
    final copy = AppLocalizations.of(context);
    if (_failed) {
      return StaffErrorState(
        message: copy.text(
          'This report could not be loaded.',
          'Nie udało się wczytać zgłoszenia.',
        ),
        onRetry: () => unawaited(_load()),
      );
    }
    final detail = _detail;
    if (detail == null) {
      return Center(
        child: Semantics(
          label: copy.text('Loading report', 'Wczytywanie zgłoszenia'),
          child: const CircularProgressIndicator(),
        ),
      );
    }
    const label = TextStyle(
      color: StaffCenterStyle.faint,
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: .3,
    );
    const value = TextStyle(color: Colors.white, fontSize: 13);
    return ListView(
      key: const ValueKey('staff-bug-report-detail'),
      padding: const EdgeInsets.all(14),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final status in bugReportStatuses)
              ChoiceChip(
                label: Text(bugReportStatusLabel(copy, status)),
                selected: _status == status,
                onSelected: _saving || _status == status
                    ? null
                    : (_) => unawaited(_setStatus(status)),
                labelStyle: TextStyle(
                  color: _status == status
                      ? Colors.white
                      : StaffCenterStyle.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                selectedColor: _statusColor(status).withValues(alpha: .35),
                backgroundColor: StaffCenterStyle.surfaceRaised,
                side: const BorderSide(color: StaffCenterStyle.border),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(copy.text('DESCRIPTION', 'OPIS'), style: label),
        const SizedBox(height: 6),
        SelectableText(detail.description, style: value),
        const SizedBox(height: 16),
        Text(copy.text('REPORTER', 'ZGŁASZAJĄCY'), style: label),
        const SizedBox(height: 4),
        if (detail.summary.reporterId != null)
          CopyableUid(uid: detail.summary.reporterId!),
        const SizedBox(height: 16),
        Text(
          copy.text('DEVICE AND APP', 'URZĄDZENIE I APLIKACJA'),
          style: label,
        ),
        const SizedBox(height: 6),
        for (final entry in detail.context.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    entry.key,
                    style: const TextStyle(
                      color: StaffCenterStyle.muted,
                      fontSize: 12,
                    ),
                  ),
                ),
                Expanded(
                  child: SelectableText(
                    entry.value,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        Text(copy.text('SCREENSHOT', 'ZRZUT EKRANU'), style: label),
        const SizedBox(height: 6),
        if (detail.screenshotUrl == null)
          Text(
            copy.text('No screenshot.', 'Brak zrzutu ekranu.'),
            style: const TextStyle(color: StaffCenterStyle.muted, fontSize: 13),
          )
        else
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 520),
              child: Image.network(
                detail.screenshotUrl!,
                fit: BoxFit.contain,
                semanticLabel: copy.text(
                  'Screenshot attached to the report',
                  'Zrzut ekranu dołączony do zgłoszenia',
                ),
                errorBuilder: (context, _, _) => Text(
                  copy.text(
                    'The screenshot link expired. Reload the report.',
                    'Link do zrzutu wygasł. Wczytaj zgłoszenie ponownie.',
                  ),
                  style: const TextStyle(
                    color: StaffCenterStyle.muted,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
        if (detail.delivery.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(copy.text('ALERTS', 'POWIADOMIENIA'), style: label),
          const SizedBox(height: 6),
          for (final entry in detail.delivery.entries)
            Text(
              '${entry.key}: ${entry.value}',
              style: const TextStyle(
                color: StaffCenterStyle.muted,
                fontSize: 12,
              ),
            ),
        ],
        const SizedBox(height: 16),
        SelectableText(
          detail.summary.reportId,
          style: const TextStyle(
            color: StaffCenterStyle.faint,
            fontSize: 10.5,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}
