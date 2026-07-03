import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

class ProgramPickerItem {
  final String id;
  final String label;
  final String? subtitle;
  final IconData? icon;
  final Color? accentColor;

  const ProgramPickerItem({
    required this.id,
    required this.label,
    this.subtitle,
    this.icon,
    this.accentColor,
  });
}

/// Tek seçim — arama destekli bottom sheet
Future<String?> showProgramSinglePickerSheet({
  required BuildContext context,
  required String title,
  required String subtitle,
  required List<ProgramPickerItem> items,
  String? selectedId,
  IconData headerIcon = Icons.tune_rounded,
  bool searchable = true,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _PickerSheet(
      title: title,
      subtitle: subtitle,
      headerIcon: headerIcon,
      items: items,
      selectedIds: selectedId != null ? {selectedId} : {},
      multiSelect: false,
      searchable: searchable,
    ),
  );
}

/// Çoklu seçim — arama destekli bottom sheet
Future<Set<String>?> showProgramMultiPickerSheet({
  required BuildContext context,
  required String title,
  required String subtitle,
  required List<ProgramPickerItem> items,
  Set<String> selectedIds = const {},
  IconData headerIcon = Icons.people_outline_rounded,
}) {
  return showModalBottomSheet<Set<String>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _PickerSheet(
      title: title,
      subtitle: subtitle,
      headerIcon: headerIcon,
      items: items,
      selectedIds: selectedIds,
      multiSelect: true,
      searchable: true,
    ),
  );
}

class ProgramEditorPickerField extends StatelessWidget {
  final String label;
  final String? valueText;
  final String hintText;
  final VoidCallback? onTap;
  final bool enabled;

  const ProgramEditorPickerField({
    super.key,
    required this.label,
    this.valueText,
    required this.hintText,
    this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasValue = valueText != null && valueText!.trim().isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            labelStyle: TextStyle(color: cs.onSurfaceVariant),
            filled: true,
            fillColor: enabled
                ? cs.surfaceContainerHighest
                : cs.surfaceContainerHigh.withValues(alpha: 0.6),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: cs.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: cs.outlineVariant),
            ),
            suffixIcon: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: enabled ? cs.onSurfaceVariant : cs.outline,
            ),
          ),
          child: Text(
            hasValue ? valueText! : hintText,
            style: AppTypography.bodyMedium.copyWith(
              color: hasValue ? cs.onSurface : cs.onSurfaceVariant,
              fontWeight: hasValue ? FontWeight.w600 : FontWeight.normal,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

class ProgramEditorMultiPickerField extends StatelessWidget {
  final String label;
  final List<ProgramPickerItem> selectedItems;
  final String hintText;
  final VoidCallback? onTap;
  final bool enabled;

  const ProgramEditorMultiPickerField({
    super.key,
    required this.label,
    required this.selectedItems,
    required this.hintText,
    this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            labelStyle: TextStyle(color: cs.onSurfaceVariant),
            filled: true,
            fillColor: cs.surfaceContainerHighest,
            contentPadding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: cs.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: cs.outlineVariant),
            ),
            suffixIcon: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: enabled ? cs.onSurfaceVariant : cs.outline,
            ),
          ),
          child: selectedItems.isEmpty
              ? Text(
                  hintText,
                  style: AppTypography.bodyMedium.copyWith(color: cs.onSurfaceVariant),
                )
              : Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: selectedItems
                      .map(
                        (item) => Chip(
                          label: Text(
                            item.label,
                            style: AppTypography.labelSmall.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppColors.secondary,
                            ),
                          ),
                          backgroundColor: AppColors.secondary.withValues(alpha: 0.12),
                          side: BorderSide.none,
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                        ),
                      )
                      .toList(),
                ),
        ),
      ),
    );
  }
}

class _PickerSheet extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData headerIcon;
  final List<ProgramPickerItem> items;
  final Set<String> selectedIds;
  final bool multiSelect;
  final bool searchable;

  const _PickerSheet({
    required this.title,
    required this.subtitle,
    required this.headerIcon,
    required this.items,
    required this.selectedIds,
    required this.multiSelect,
    required this.searchable,
  });

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  late Set<String> _selected;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.selectedIds);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ProgramPickerItem> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.items;
    return widget.items.where((item) {
      final label = item.label.toLowerCase();
      final sub = (item.subtitle ?? '').toLowerCase();
      return label.contains(q) || sub.contains(q);
    }).toList();
  }

  void _toggle(String id) {
    setState(() {
      if (widget.multiSelect) {
        if (_selected.contains(id)) {
          _selected.remove(id);
        } else {
          _selected.add(id);
        }
      } else {
        _selected = {id};
        Navigator.pop(context, id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final filtered = _filtered;
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(widget.headerIcon, color: cs.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: AppTypography.titleMedium.copyWith(
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                          ),
                          Text(
                            widget.subtitle,
                            style: AppTypography.bodySmall.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(
                        context,
                        widget.multiSelect ? _selected : null,
                      ),
                      icon: Icon(Icons.close, color: cs.onSurfaceVariant),
                      tooltip: widget.multiSelect ? 'Seçimi uygula' : 'Kapat',
                    ),
                  ],
                ),
              ),
              if (widget.searchable) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _query = v),
                    style: TextStyle(color: cs.onSurface),
                    decoration: InputDecoration(
                      hintText: 'Ara…',
                      prefixIcon: Icon(Icons.search_rounded, color: cs.onSurfaceVariant),
                      filled: true,
                      fillColor: cs.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (widget.multiSelect)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () => setState(() => _selected = widget.items.map((e) => e.id).toSet()),
                        child: const Text('Tümünü seç'),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _selected.clear()),
                        child: const Text('Temizle'),
                      ),
                      const Spacer(),
                      if (_selected.isNotEmpty)
                        Text(
                          '${_selected.length} seçili',
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.secondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
              const Divider(height: 1),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          'Sonuç bulunamadı',
                          style: AppTypography.bodyMedium.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          final isSelected = _selected.contains(item.id);
                          final accent = item.accentColor ?? cs.primary;

                          return Material(
                            color: isSelected
                                ? accent.withValues(alpha: 0.12)
                                : cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              onTap: () => _toggle(item.id),
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                child: Row(
                                  children: [
                                    if (item.icon != null)
                                      CircleAvatar(
                                        radius: 18,
                                        backgroundColor: accent.withValues(alpha: 0.15),
                                        child: Icon(item.icon, size: 18, color: accent),
                                      )
                                    else if (widget.multiSelect)
                                      Checkbox(
                                        value: isSelected,
                                        onChanged: (_) => _toggle(item.id),
                                        activeColor: AppColors.secondary,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                      ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.label,
                                            style: AppTypography.bodyMedium.copyWith(
                                              fontWeight: FontWeight.w600,
                                              color: cs.onSurface,
                                            ),
                                          ),
                                          if (item.subtitle != null && item.subtitle!.isNotEmpty)
                                            Text(
                                              item.subtitle!,
                                              style: AppTypography.labelSmall.copyWith(
                                                color: cs.onSurfaceVariant,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    if (!widget.multiSelect && isSelected)
                                      Icon(Icons.check_circle_rounded, color: accent, size: 22),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
