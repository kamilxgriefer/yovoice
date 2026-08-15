import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The Staff Center's shared visual vocabulary — one place for the
/// palette and the small pieces every section reuses, so seven sections
/// read as one screen.
abstract final class StaffCenterStyle {
  static const background = Color(0xFF080711);
  static const surface = Color(0xFF14101F);
  static const surfaceRaised = Color(0xFF1B1428);
  static const border = Color(0xFF32263F);
  static const muted = Color(0xFFA69CAF);
  static const faint = Color(0xFF7E7490);
  static const accent = Color(0xFF9D20FF);
  static const good = Color(0xFF35D07F);
  static const warn = Color(0xFFFFB547);
  static const bad = Color(0xFFFF5F6D);
}

String staffStamp(DateTime? at) {
  if (at == null) return '—';
  final local = at.toLocal();
  final now = DateTime.now();
  final difference = now.difference(local);
  if (difference.inMinutes < 1) return 'now';
  if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
  if (difference.inHours < 24) return '${difference.inHours}h ago';
  if (difference.inDays < 7) return '${difference.inDays}d ago';
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}

class StaffSectionHeader extends StatelessWidget {
  const StaffSectionHeader({
    required this.title,
    required this.subtitle,
    this.trailing,
    super.key,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: -.3,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: const TextStyle(
            color: StaffCenterStyle.muted,
            fontSize: 12.5,
            height: 1.35,
          ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      // On a phone the trailing action drops UNDER the title instead of
      // squeezing beside it — same content, no horizontal overflow.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 520 && trailing != null;
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleBlock,
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerLeft, child: trailing),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: titleBlock),
              ?trailing,
            ],
          );
        },
      ),
    );
  }
}

class StaffPanel extends StatelessWidget {
  const StaffPanel({required this.child, this.padding, super.key});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: StaffCenterStyle.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: StaffCenterStyle.border),
      ),
      child: child,
    );
  }
}

class StaffPanelTitle extends StatelessWidget {
  const StaffPanelTitle({required this.title, this.onSeeAll, super.key});

  final String title;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (onSeeAll != null)
            TextButton(
              onPressed: onSeeAll,
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 32),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                foregroundColor: const Color(0xFFD3A5FF),
              ),
              child: const Text('Open', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

/// The honest empty state: a quiet line, not a large blank area.
class StaffEmptyState extends StatelessWidget {
  const StaffEmptyState({required this.message, this.icon, super.key});

  final String message;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 26),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon ?? Icons.check_circle_outline_rounded,
              color: StaffCenterStyle.faint,
              size: 26,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: StaffCenterStyle.muted,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An error state that names its kind and offers a way forward — an
/// error is never dressed up as "no results".
class StaffErrorState extends StatelessWidget {
  const StaffErrorState({
    required this.message,
    required this.onRetry,
    this.onClear,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: StaffCenterStyle.bad,
              size: 26,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: StaffCenterStyle.muted,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(
                  onPressed: onRetry,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: StaffCenterStyle.border),
                  ),
                  child: const Text('Retry'),
                ),
                if (onClear != null) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: onClear,
                    style: TextButton.styleFrom(
                      foregroundColor: StaffCenterStyle.muted,
                    ),
                    child: const Text('Clear'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The uid, monospaced and copyable in one tap — every identity row and
/// header carries one.
class CopyableUid extends StatelessWidget {
  const CopyableUid({required this.uid, super.key});

  final String uid;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            uid,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: StaffCenterStyle.faint,
              fontSize: 10.5,
              fontFamily: 'monospace',
            ),
          ),
        ),
        const SizedBox(width: 2),
        Tooltip(
          message: 'Copy uid',
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () async {
              // Captured before the await: the context may unmount while
              // the clipboard call runs.
              final messenger = ScaffoldMessenger.maybeOf(context);
              await Clipboard.setData(ClipboardData(text: uid));
              messenger?.showSnackBar(
                const SnackBar(
                  content: Text('User id copied.'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(
                Icons.copy_rounded,
                size: 12,
                color: StaffCenterStyle.faint,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// ACTIVE / MUTED / BANNED, colored by weight.
class AccountStatusChip extends StatelessWidget {
  const AccountStatusChip({required this.status, super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'BANNED' => StaffCenterStyle.bad,
      'MUTED' || 'SUSPENDED' => StaffCenterStyle.warn,
      _ => StaffCenterStyle.good,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: .45)),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
          letterSpacing: .5,
        ),
      ),
    );
  }
}
