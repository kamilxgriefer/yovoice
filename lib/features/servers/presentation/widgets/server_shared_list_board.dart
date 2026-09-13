import 'package:flutter/material.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';

import '../../data/models/server_channel.dart';
import '../../data/models/server_list_item.dart';
import '../../data/models/server_member_role.dart';
import '../../data/services/server_shared_list_service.dart';
import '../server_action_failure.dart';
import '../server_localized_copy.dart';
import '../theme/server_identity.dart';

class ServerSharedListBoard extends StatefulWidget {
  const ServerSharedListBoard({
    required this.serverId,
    required this.channel,
    required this.repository,
    required this.colors,
    this.role,
    this.compact = false,
    super.key,
  });

  final String serverId;
  final ServerChannel channel;
  final ServerSharedListRepository repository;
  final ServerIdentityVisuals colors;
  final ServerMemberRole? role;
  final bool compact;

  @override
  State<ServerSharedListBoard> createState() => _ServerSharedListBoardState();
}

class _ServerSharedListBoardState extends State<ServerSharedListBoard> {
  final _composer = TextEditingController();
  final _focus = FocusNode();
  late Stream<List<ServerListItem>> _items;
  bool _creating = false;
  final _busyItems = <String>{};
  Object? _error;

  bool get _canWrite => widget.role != ServerMemberRole.guest;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(covariant ServerSharedListBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.serverId != widget.serverId ||
        oldWidget.channel.id != widget.channel.id ||
        oldWidget.repository != widget.repository) {
      _bind();
    }
  }

  void _bind() {
    _items = widget.repository.watchItems(widget.serverId, widget.channel.id);
  }

  @override
  void dispose() {
    _composer.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final value = _composer.text.trim();
    if (!_canWrite || _creating || value.isEmpty) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      await widget.repository.createItem(
        serverId: widget.serverId,
        channelId: widget.channel.id,
        text: value,
        requestId: widget.repository.newRequestId(),
      );
      if (!mounted) return;
      _composer.clear();
      _focus.requestFocus();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _update(ServerListItem item, Map<String, Object?> patch) async {
    if (!_canWrite || _busyItems.contains(item.id)) return;
    setState(() {
      _busyItems.add(item.id);
      _error = null;
    });
    try {
      await widget.repository.updateItem(
        item: item,
        patch: patch,
        requestId: widget.repository.newRequestId(),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busyItems.remove(item.id));
    }
  }

  Future<void> _edit(ServerListItem item) async {
    final copy = AppLocalizations.of(context);
    final controller = TextEditingController(text: item.text);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(copy.text('Edit item', 'Edytuj produkt')),
        content: TextField(
          key: const ValueKey('server-list-edit-field'),
          controller: controller,
          autofocus: true,
          maxLength: 160,
          textInputAction: TextInputAction.done,
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              Navigator.of(context).pop(value.trim());
            }
          },
          decoration: InputDecoration(labelText: copy.text('Item', 'Produkt')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(copy.serverCancel),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.of(context).pop(value);
            },
            child: Text(copy.text('Save', 'Zapisz')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null && value != item.text) {
      await _update(item, {'text': value});
    }
  }

  Future<void> _delete(ServerListItem item) async {
    final copy = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(copy.text('Remove this item?', 'Usunąć ten produkt?')),
        content: Text(item.text),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(copy.serverCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(copy.text('Remove', 'Usuń')),
          ),
        ],
      ),
    );
    if (confirmed != true || _busyItems.contains(item.id)) return;
    setState(() {
      _busyItems.add(item.id);
      _error = null;
    });
    try {
      await widget.repository.deleteItem(
        item: item,
        requestId: widget.repository.newRequestId(),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busyItems.remove(item.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    return Material(
      key: const ValueKey('server-shared-list-board'),
      color: palette.background,
      child: StreamBuilder<List<ServerListItem>>(
        stream: _items,
        builder: (context, snapshot) {
          final items = snapshot.data ?? const <ServerListItem>[];
          return ListView(
            key: const ValueKey('server-channel-content-scroll'),
            padding: EdgeInsets.all(
              widget.compact ? AppSpacing.md : AppSpacing.lg,
            ),
            children: [
              _Header(colors: widget.colors, compact: widget.compact),
              const SizedBox(height: AppSpacing.lg),
              if (_canWrite)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('server-list-composer'),
                        controller: _composer,
                        focusNode: _focus,
                        maxLength: 160,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _create(),
                        decoration: InputDecoration(
                          labelText: copy.text('Add an item', 'Dodaj produkt'),
                          hintText: copy.text(
                            'For example: bread',
                            'Np. chleb',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    IconButton.filled(
                      key: const ValueKey('server-list-add'),
                      onPressed: _creating ? null : _create,
                      tooltip: copy.text('Add item', 'Dodaj produkt'),
                      style: IconButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        backgroundColor: widget.colors.cta,
                        foregroundColor: widget.colors.onCta,
                      ),
                      icon: _creating
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_rounded),
                    ),
                  ],
                ),
              if (_error case final error?) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  serverActionFailureCopy(
                    error,
                    copy,
                    fallback: copy.text(
                      'The list could not be updated. Try again.',
                      'Nie udało się zaktualizować listy. Spróbuj ponownie.',
                    ),
                  ),
                  key: const ValueKey('server-list-error'),
                  style: AppTypography.bodySmall.copyWith(
                    color: palette.dangerForeground,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData)
                const Center(child: CircularProgressIndicator())
              else if (snapshot.hasError)
                Text(
                  copy.text(
                    'The shared list is unavailable.',
                    'Wspólna lista jest niedostępna.',
                  ),
                  style: AppTypography.bodyMedium.copyWith(
                    color: palette.dangerForeground,
                  ),
                )
              else if (items.isEmpty)
                _Empty(colors: widget.colors)
              else
                Container(
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: AppRadius.lg,
                    border: Border.all(color: palette.border),
                  ),
                  child: Column(
                    children: [
                      for (var index = 0; index < items.length; index++) ...[
                        if (index > 0)
                          Divider(height: 1, color: palette.border),
                        _ItemRow(
                          item: items[index],
                          busy: _busyItems.contains(items[index].id),
                          canWrite: _canWrite,
                          canDelete:
                              items[index].createdById ==
                                  widget.repository.currentUserId ||
                              (widget.role?.canModerate ?? false),
                          onToggle: () => _update(items[index], {
                            'checked': !items[index].checked,
                          }),
                          onEdit: () => _edit(items[index]),
                          onDelete: () => _delete(items[index]),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.colors, required this.compact});
  final ServerIdentityVisuals colors;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: compact ? 48 : 56,
          height: compact ? 48 : 56,
          decoration: BoxDecoration(
            color: colors.iconSurface,
            borderRadius: AppRadius.md,
            border: Border.all(color: colors.iconBorder),
          ),
          child: Icon(Icons.shopping_cart_outlined, color: colors.foreground),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                copy.text('Shared shopping list', 'Wspólna lista zakupów'),
                style:
                    (compact
                            ? AppTypography.titleLarge
                            : AppTypography.headlineSmall)
                        .copyWith(color: palette.textPrimary),
              ),
              const SizedBox(height: 4),
              Text(
                copy.text(
                  'Everyone sees changes as they happen.',
                  'Każdy widzi zmiany od razu.',
                ),
                style: AppTypography.bodyMedium.copyWith(
                  color: palette.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.colors});
  final ServerIdentityVisuals colors;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadius.lg,
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          Icon(Icons.checklist_rounded, size: 48, color: colors.foreground),
          const SizedBox(height: AppSpacing.md),
          Text(
            copy.text('The list is empty', 'Lista jest pusta'),
            style: AppTypography.titleLarge.copyWith(
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            copy.text(
              'Add the first thing your family needs.',
              'Dodaj pierwszą rzecz, której potrzebuje rodzina.',
            ),
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.busy,
    required this.canWrite,
    required this.canDelete,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final ServerListItem item;
  final bool busy;
  final bool canWrite;
  final bool canDelete;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    return Semantics(
      label: item.checked
          ? copy.template(
              '#{item}, completed',
              '#{item}, kupione',
              values: {'item': item.text},
            )
          : item.text,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 4, 6),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 48,
              child: Center(
                child: busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Checkbox(
                        key: ValueKey('server-list-toggle-${item.id}'),
                        value: item.checked,
                        onChanged: canWrite ? (_) => onToggle() : null,
                      ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                item.text,
                style: AppTypography.bodyLarge.copyWith(
                  color: item.checked
                      ? palette.textSecondary
                      : palette.textPrimary,
                  decoration: item.checked ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            if (canWrite)
              PopupMenuButton<String>(
                key: ValueKey('server-list-menu-${item.id}'),
                tooltip: copy.text('Item options', 'Opcje produktu'),
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: Text(copy.text('Edit', 'Edytuj')),
                  ),
                  if (canDelete)
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(copy.text('Remove', 'Usuń')),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
