import 'package:flutter/material.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_typography.dart';

import '../../data/models/server.dart';
import '../../data/models/server_channel.dart';
import '../../data/models/server_member_role.dart';
import '../../data/models/server_podcast_question.dart';
import '../../data/models/server_type.dart';
import '../../data/services/server_service.dart';
import '../server_action_failure.dart';
import '../server_localized_copy.dart';
import '../theme/server_identity.dart';

/// Durable listener Q&A for a podcast server's Questions channel.
class ServerPodcastQuestionsBoard extends StatefulWidget {
  const ServerPodcastQuestionsBoard({
    required this.server,
    required this.channel,
    required this.repository,
    required this.role,
    this.compact = false,
    super.key,
  });

  final Server server;
  final ServerChannel channel;
  final ServerRepository repository;
  final ServerMemberRole? role;
  final bool compact;

  @override
  State<ServerPodcastQuestionsBoard> createState() =>
      _ServerPodcastQuestionsBoardState();
}

class _ServerPodcastQuestionsBoardState
    extends State<ServerPodcastQuestionsBoard> {
  final _composer = TextEditingController();
  String? _busyId;
  String? _error;

  ServerPodcastQuestionsRepository? get _questions =>
      widget.repository is ServerPodcastQuestionsRepository
      ? widget.repository as ServerPodcastQuestionsRepository
      : null;

  bool get _canAsk =>
      widget.role != null &&
      widget.role != ServerMemberRole.guest &&
      !widget.server.isHeld;

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  Future<bool> _run(String id, Future<void> Function() action) async {
    if (_busyId != null) return false;
    setState(() {
      _busyId = id;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return true;
      setState(() => _busyId = null);
      return true;
    } catch (error) {
      if (!mounted) return false;
      setState(() {
        _busyId = null;
        _error = serverActionFailureCopy(error, AppLocalizations.of(context));
      });
      return false;
    }
  }

  Future<void> _submit() async {
    final service = _questions;
    final body = _composer.text.trim();
    if (service == null || !_canAsk || body.isEmpty || body.length > 500) {
      return;
    }
    final sent = await _run(
      'create',
      () => service.createPodcastQuestion(
        serverId: widget.server.id,
        channelId: widget.channel.id,
        body: body,
        requestId: widget.repository.newRequestId(),
      ),
    );
    if (sent && mounted && _composer.text.trim() == body) {
      _composer.clear();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final service = _questions;
    if (service == null) {
      return Center(child: Text(copy.serverActionUnavailable));
    }
    return Material(
      color: Colors.transparent,
      child: StreamBuilder<List<ServerPodcastQuestion>>(
        stream: service.watchPodcastQuestions(
          widget.server.id,
          widget.channel.id,
        ),
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
          final questions = snapshot.data!;
          final horizontal = widget.compact ? 12.0 : 16.0;
          return CustomScrollView(
            key: const ValueKey('server-podcast-questions-board'),
            slivers: [
              SliverToBoxAdapter(
                child: _QuestionsHeader(
                  server: widget.server,
                  compact: widget.compact,
                ),
              ),
              if (_canAsk)
                SliverToBoxAdapter(
                  child: _QuestionComposer(
                    controller: _composer,
                    compact: widget.compact,
                    busy: _busyId != null,
                    onChanged: () => setState(() {}),
                    onSubmit: _submit,
                  ),
                ),
              if (_error != null)
                SliverToBoxAdapter(
                  child: Semantics(
                    liveRegion: true,
                    child: Container(
                      key: const ValueKey('server-podcast-question-error'),
                      margin: EdgeInsets.fromLTRB(
                        horizontal,
                        0,
                        horizontal,
                        10,
                      ),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: palette.dangerSurface,
                        borderRadius: AppRadius.md,
                      ),
                      child: Text(
                        _error!,
                        style: TextStyle(color: palette.dangerForeground),
                      ),
                    ),
                  ),
                ),
              if (questions.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Text(
                        copy.serverPodcastNoQuestions,
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
                  padding: EdgeInsets.fromLTRB(horizontal, 4, horizontal, 28),
                  sliver: SliverList.separated(
                    itemCount: questions.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final question = questions[index];
                      return _QuestionCard(
                        question: question,
                        vote: service.watchMyPodcastQuestionVote(
                          question.serverId,
                          question.channelId,
                          question.id,
                        ),
                        canVote: _canAsk,
                        canModerate: widget.role?.canModerate ?? false,
                        busy: _busyId == question.id,
                        onVote: (voted) => _run(
                          question.id,
                          () => service.setPodcastQuestionVote(
                            question: question,
                            voted: voted,
                            requestId: widget.repository.newRequestId(),
                          ),
                        ),
                        onAir: (onAir) => _run(
                          question.id,
                          () => service.setPodcastQuestionOnAir(
                            question: question,
                            onAir: onAir,
                            requestId: widget.repository.newRequestId(),
                          ),
                        ),
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
}

class _QuestionsHeader extends StatelessWidget {
  const _QuestionsHeader({required this.server, required this.compact});

  final Server server;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = ServerIdentity.of(
      server.type,
    ).resolve(Theme.of(context).brightness);
    return Semantics(
      header: true,
      child: Container(
        margin: EdgeInsets.fromLTRB(
          compact ? 12 : 16,
          compact ? 12 : 16,
          compact ? 12 : 16,
          10,
        ),
        padding: EdgeInsets.all(compact ? 16 : 20),
        decoration: BoxDecoration(
          color: colors.cardWash,
          borderRadius: AppRadius.xl,
          border: Border.all(color: colors.iconBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.question_answer_outlined,
              size: compact ? 26 : 30,
              color: colors.foreground,
            ),
            const SizedBox(height: 10),
            Text(
              copy.serverPodcastQuestionsTitle,
              style:
                  (compact
                          ? AppTypography.titleMedium
                          : AppTypography.headlineSmall)
                      .copyWith(color: palette.textPrimary),
            ),
            const SizedBox(height: 5),
            Text(
              copy.serverPodcastQuestionsBody,
              style: AppTypography.bodySmall.copyWith(
                color: palette.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestionComposer extends StatelessWidget {
  const _QuestionComposer({
    required this.controller,
    required this.compact,
    required this.busy,
    required this.onChanged,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool compact;
  final bool busy;
  final VoidCallback onChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final canSend = !busy && controller.text.trim().isNotEmpty;
    return Container(
      margin: EdgeInsets.fromLTRB(compact ? 12 : 16, 0, compact ? 12 : 16, 10),
      padding: const EdgeInsets.fromLTRB(14, 8, 10, 10),
      decoration: BoxDecoration(
        color: context.appPalette.surface,
        borderRadius: AppRadius.lg,
        border: Border.all(color: context.appPalette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('server-podcast-question-composer'),
            controller: controller,
            enabled: !busy,
            minLines: 1,
            maxLines: compact ? 3 : 4,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => onChanged(),
            onSubmitted: (_) {
              if (canSend) onSubmit();
            },
            decoration: InputDecoration(
              labelText: copy.serverPodcastAskQuestion,
              hintText: copy.serverPodcastQuestionHint,
              border: InputBorder.none,
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.icon(
              key: const ValueKey('server-podcast-question-send'),
              onPressed: canSend ? onSubmit : null,
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              icon: const Icon(Icons.send_rounded, size: 19),
              label: Text(copy.serverPodcastSendQuestion),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.question,
    required this.vote,
    required this.canVote,
    required this.canModerate,
    required this.busy,
    required this.onVote,
    required this.onAir,
  });

  final ServerPodcastQuestion question;
  final Stream<bool> vote;
  final bool canVote;
  final bool canModerate;
  final bool busy;
  final ValueChanged<bool> onVote;
  final ValueChanged<bool> onAir;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final identity = ServerIdentity.of(
      ServerType.podcast,
    ).resolve(Theme.of(context).brightness);
    return Semantics(
      container: true,
      label:
          '${question.authorName}. ${question.body}. '
          '${copy.serverPodcastVotes(question.voteCount)}',
      child: Container(
        key: ValueKey('server-podcast-question-${question.id}'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: question.isOnAir ? identity.cardWash : palette.surface,
          borderRadius: AppRadius.lg,
          border: Border.all(
            color: question.isOnAir ? identity.foreground : palette.border,
            width: question.isOnAir ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  question.authorName,
                  style: AppTypography.labelLarge.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
                if (question.isOnAir)
                  Semantics(
                    label: copy.serverPodcastOnAir,
                    child: Container(
                      key: ValueKey(
                        'server-podcast-question-on-air-${question.id}',
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: identity.cta,
                        borderRadius: AppRadius.pill,
                      ),
                      child: Text(
                        copy.serverPodcastOnAir.toUpperCase(),
                        style: AppTypography.labelSmall.copyWith(
                          color: identity.onCta,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              question.body,
              style: AppTypography.bodyLarge.copyWith(
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 14),
            StreamBuilder<bool>(
              stream: vote,
              initialData: false,
              builder: (context, snapshot) {
                final voted = snapshot.data ?? false;
                final voteAvailable =
                    canVote && !busy && !snapshot.hasError && snapshot.hasData;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      key: ValueKey(
                        'server-podcast-question-vote-${question.id}',
                      ),
                      onPressed: voteAvailable ? () => onVote(!voted) : null,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      icon: Icon(
                        voted
                            ? Icons.thumb_up_alt_rounded
                            : Icons.thumb_up_alt_outlined,
                        size: 19,
                      ),
                      label: Text(
                        '${voted ? copy.serverPodcastRemoveVote : copy.serverPodcastVote} '
                        '· ${copy.serverPodcastVotes(question.voteCount)}',
                      ),
                    ),
                    if (canModerate)
                      TextButton.icon(
                        key: ValueKey(
                          'server-podcast-question-air-${question.id}',
                        ),
                        onPressed: busy ? null : () => onAir(!question.isOnAir),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, 48),
                        ),
                        icon: Icon(
                          question.isOnAir
                              ? Icons.stop_circle_outlined
                              : Icons.podcasts_rounded,
                          size: 19,
                        ),
                        label: Text(
                          question.isOnAir
                              ? copy.serverPodcastRemoveFromAir
                              : copy.serverPodcastPutOnAir,
                        ),
                      ),
                  ],
                );
              },
            ),
            if (busy) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(minHeight: 2),
            ],
          ],
        ),
      ),
    );
  }
}
