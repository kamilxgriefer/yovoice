import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_sizing.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_expiry_accessibility.dart';

/// One composed assertive error channel for a Home surface (ADR-058).
///
/// The visible section copy stays independently readable. Error episodes,
/// rather than rebuilds or raw provider exception identities, drive speech.
class HomeErrorAnnouncementScope extends StatefulWidget {
  const HomeErrorAnnouncementScope({
    required this.child,
    this.isVisible,
    super.key,
  });

  final Widget child;
  final ValueListenable<bool>? isVisible;

  @override
  State<HomeErrorAnnouncementScope> createState() =>
      _HomeErrorAnnouncementScopeState();
}

class _HomeErrorAnnouncementScopeState
    extends State<HomeErrorAnnouncementScope> {
  final _errors = <Object, ({BuildContext context, String message})>{};
  final _announced = <String>{};
  bool _flushScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.isVisible?.addListener(_scheduleFlush);
  }

  @override
  void didUpdateWidget(covariant HomeErrorAnnouncementScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isVisible != widget.isVisible) {
      oldWidget.isVisible?.removeListener(_scheduleFlush);
      widget.isVisible?.addListener(_scheduleFlush);
    }
  }

  void report(Object source, BuildContext context, String message) {
    _errors[source] = (context: context, message: message.trim());
    _scheduleFlush();
  }

  void remove(Object source) {
    _errors.remove(source);
    _scheduleFlush();
  }

  void _scheduleFlush() {
    if (!mounted || _flushScheduled) return;
    _flushScheduled = true;
    // Compose after descendants have reported this frame, then wait for the
    // next rendered update. A withdrawn error, disposed route or replacement
    // message can invalidate queued speech before it leaves the app.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _flushScheduled = false;
        if (mounted) _flush();
      });
      WidgetsBinding.instance.scheduleFrame();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _flush() {
    _errors.removeWhere((_, error) => !error.context.mounted);
    final currentMessages = _errors.values
        .map((error) => error.message)
        .where((message) => message.isNotEmpty)
        .toSet();
    // Resolution closes the episode, even on a retained hidden tab. A later
    // identical failure is new; an unchanged active error is not.
    _announced.removeWhere((message) => !currentMessages.contains(message));
    if (widget.isVisible?.value == false ||
        !momentExpirySurfaceIsVisible(context)) {
      return;
    }
    final pending = _errors.values
        .where((error) => momentExpirySurfaceIsVisible(error.context))
        .map((error) => error.message)
        .where((message) => message.isNotEmpty && !_announced.contains(message))
        .toSet();
    if (pending.isEmpty) return;
    _announced.addAll(pending);
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        pending.join('\n'),
        Directionality.of(context),
        assertiveness: Assertiveness.assertive,
      ),
    );
  }

  @override
  void dispose() {
    widget.isVisible?.removeListener(_scheduleFlush);
    _errors.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _scheduleFlush();
    return _HomeErrorChannel(owner: this, child: widget.child);
  }
}

class _HomeErrorChannel extends InheritedWidget {
  const _HomeErrorChannel({required this.owner, required super.child});

  final _HomeErrorAnnouncementScopeState owner;

  static _HomeErrorAnnouncementScopeState? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_HomeErrorChannel>()?.owner;

  @override
  bool updateShouldNotify(_HomeErrorChannel oldWidget) =>
      owner != oldWidget.owner;
}

/// A local Home read failure, not a whole-page error or an empty feed.
///
/// The compact surface leaves the working sections usable. Raw provider
/// errors never become copy, and the action uses the caller's existing read.
class HomeSectionError extends StatelessWidget {
  const HomeSectionError({
    required this.message,
    required this.onRetry,
    this.error,
    super.key,
  });

  final String message;
  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final content = _HomeSectionErrorContent(
      message: message,
      error: error,
      onRetry: onRetry,
    );
    // Shared Home components also have standalone callers. Keep that public
    // contract accessible without creating another scope inside a real Home.
    return _HomeErrorChannel.maybeOf(context) == null
        ? HomeErrorAnnouncementScope(child: content)
        : content;
  }
}

class _HomeSectionErrorContent extends StatefulWidget {
  const _HomeSectionErrorContent({
    required this.message,
    required this.error,
    required this.onRetry,
  });

  final String message;
  final Object? error;
  final VoidCallback? onRetry;

  @override
  State<_HomeSectionErrorContent> createState() =>
      _HomeSectionErrorContentState();
}

class _HomeSectionErrorContentState extends State<_HomeSectionErrorContent> {
  _HomeErrorAnnouncementScopeState? _channel;

  @override
  void dispose() {
    _channel?.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final safeMessage = widget.error == null
        ? widget.message
        : friendlyErrorMessage(
            widget.error!,
            fallback: widget.message,
            copy: copy,
          );
    final channel = _HomeErrorChannel.maybeOf(context);
    if (_channel != channel) _channel?.remove(this);
    _channel = channel;
    channel?.report(this, context, safeMessage);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadius.lg,
        border: Border.all(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppRhythm.title),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              container: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: Icon(
                      Icons.cloud_off_outlined,
                      color: palette.textSecondary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: AppRhythm.item),
                  Expanded(
                    child: Text(
                      safeMessage,
                      style: AppTypography.bodyMedium.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (widget.onRetry != null) ...[
              const SizedBox(height: AppRhythm.item),
              OutlinedButton.icon(
                onPressed: widget.onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 20),
                label: Text(copy.text('Try again', 'Spróbuj ponownie')),
                style:
                    OutlinedButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.standard,
                      minimumSize: const Size(
                        AppSizing.minimumTouchTarget,
                        AppSizing.minimumTouchTarget,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppRhythm.title,
                        vertical: AppRhythm.tight,
                      ),
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppRadius.pill,
                      ),
                    ).copyWith(
                      side: WidgetStateProperty.resolveWith(
                        (states) => BorderSide(
                          color: states.contains(WidgetState.focused)
                              ? palette.focus
                              : palette.borderStrong,
                          width: states.contains(WidgetState.focused) ? 2 : 1,
                        ),
                      ),
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
