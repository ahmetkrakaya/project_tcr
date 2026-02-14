import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../domain/entities/event_info_block_entity.dart';
import '../providers/event_provider.dart';

/// Notion benzeri Event Info Blocks Editor
class EventInfoBlocksEditor extends ConsumerStatefulWidget {
  final String eventId;

  const EventInfoBlocksEditor({super.key, required this.eventId});

  @override
  ConsumerState<EventInfoBlocksEditor> createState() => _EventInfoBlocksEditorState();
}

class _EventInfoBlocksEditorState extends ConsumerState<EventInfoBlocksEditor> {
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    final blocksState = ref.watch(eventInfoBlocksNotifierProvider(widget.eventId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Etkinlik Bilgileri'),
        actions: [
          IconButton(
            icon: const Icon(Icons.playlist_add),
            tooltip: 'Toplu Ekle',
            onPressed: () => _showBulkAddDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Blok Ekle',
            onPressed: () => _showAddBlockDialog(context),
          ),
          blocksState.when(
            data: (_) => _isSaving
                ? const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
                  )
                : IconButton(
                    onPressed: _saveBlocks,
                    icon: const Icon(Icons.check),
                    tooltip: 'Kaydet',
                  ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: blocksState.when(
        data: (blocks) {
          if (blocks.isEmpty) {
            return _buildEmptyState();
          }

          return ReorderableListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: blocks.length,
            onReorder: (oldIndex, newIndex) {
              ref.read(eventInfoBlocksNotifierProvider(widget.eventId).notifier)
                  .reorderBlocks(oldIndex, newIndex);
            },
            itemBuilder: (context, index) {
              final block = blocks[index];
              return _buildBlockItem(context, block, index);
            },
          );
        },
        loading: () => const Center(child: LoadingWidget()),
        error: (error, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 16),
              Text('Hata: $error'),
              const SizedBox(height: 16),
              AppButton(
                text: 'Tekrar Dene',
                onPressed: () {
                  ref.read(eventInfoBlocksNotifierProvider(widget.eventId).notifier).loadBlocks();
                },
              ),
            ],
          ),
        ),
      ),
      
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.article_outlined,
              size: 64,
              color: AppColors.neutral400,
            ),
            const SizedBox(height: 16),
            Text(
              'Henüz bilgi bloğu yok',
              style: AppTypography.titleMedium.copyWith(
                color: AppColors.neutral500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Katılımcılar için program, uyarılar ve bilgiler ekleyin',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.neutral400,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            AppButton(
              text: 'İlk Bloğu Ekle',
              icon: Icons.add,
              onPressed: () => _showAddBlockDialog(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockItem(BuildContext context, EventInfoBlockEntity block, int index) {
    return Card(
      key: ValueKey(block.id),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: ReorderableDragStartListener(
          index: index,
          child: const Icon(Icons.drag_handle, color: AppColors.neutral400),
        ),
        title: Row(
          children: [
            _buildBlockTypeChip(block.type),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                block.content,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodyMedium,
              ),
            ),
          ],
        ),
        subtitle: block.subContent != null && block.subContent!.isNotEmpty
            ? Text(
                block.subContent!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySmall.copyWith(color: AppColors.neutral500),
              )
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () => _showEditBlockDialog(context, block),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.error),
              onPressed: () => _confirmDeleteBlock(context, block),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockTypeChip(EventInfoBlockType type) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _getTypeColor(type).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        type.displayName,
        style: AppTypography.labelSmall.copyWith(
          color: _getTypeColor(type),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Color _getTypeColor(EventInfoBlockType type) {
    switch (type) {
      case EventInfoBlockType.header:
        return AppColors.primary;
      case EventInfoBlockType.subheader:
        return AppColors.primaryLight;
      case EventInfoBlockType.scheduleItem:
        return AppColors.secondary;
      case EventInfoBlockType.warning:
        return AppColors.error;
      case EventInfoBlockType.info:
        return AppColors.info;
      case EventInfoBlockType.tip:
        return AppColors.success;
      case EventInfoBlockType.text:
        return AppColors.neutral600;
      case EventInfoBlockType.quote:
        return Colors.purple;
      case EventInfoBlockType.listItem:
        return AppColors.tertiary;
      case EventInfoBlockType.checklistItem:
        return AppColors.secondary;
      case EventInfoBlockType.divider:
        return AppColors.neutral400;
    }
  }

  Future<void> _saveBlocks() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final notifier = ref.read(eventInfoBlocksNotifierProvider(widget.eventId).notifier);
      final ok = await notifier.saveBlocks();
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kaydedildi')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kaydetme başarısız'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showAddBlockDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _AddBlockSheet(
        eventId: widget.eventId,
        notifier: ref.read(eventInfoBlocksNotifierProvider(widget.eventId).notifier),
      ),
    );
  }

  void _showBulkAddDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _BulkAddSheet(
        notifier: ref.read(eventInfoBlocksNotifierProvider(widget.eventId).notifier),
      ),
    );
  }

  void _showEditBlockDialog(BuildContext context, EventInfoBlockEntity block) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _EditBlockSheet(
        block: block,
        onSave: (updatedBlock) {
          ref.read(eventInfoBlocksNotifierProvider(widget.eventId).notifier)
              .updateBlock(updatedBlock);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _confirmDeleteBlock(BuildContext context, EventInfoBlockEntity block) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bloğu Sil'),
        content: const Text('Bu bloğu silmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () {
              ref.read(eventInfoBlocksNotifierProvider(widget.eventId).notifier)
                  .deleteBlock(block.id);
              Navigator.pop(context);
            },
            child: const Text('Sil', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

/// Add Block Bottom Sheet - Hızlı ekleme modu ile
class _AddBlockSheet extends StatefulWidget {
  final String eventId;
  final EventInfoBlocksNotifier notifier;

  const _AddBlockSheet({
    required this.eventId,
    required this.notifier,
  });

  @override
  State<_AddBlockSheet> createState() => _AddBlockSheetState();
}

class _AddBlockSheetState extends State<_AddBlockSheet> {
  EventInfoBlockType _selectedType = EventInfoBlockType.scheduleItem;
  final _contentController = TextEditingController();
  final _subContentController = TextEditingController();
  bool _keepAdding = true; // Hızlı ekleme modu varsayılan açık
  int _addedCount = 0;

  @override
  void dispose() {
    _contentController.dispose();
    _subContentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Blok Ekle', style: AppTypography.titleLarge),
                    if (_addedCount > 0)
                      Text(
                        '$_addedCount blok eklendi',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.success,
                        ),
                      ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            Text('Blok Türü', style: AppTypography.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: EventInfoBlockType.values.map((type) {
                if (type == EventInfoBlockType.divider) {
                  return _buildTypeChip(type, '➖ Ayırıcı');
                }
                return _buildTypeChip(type, '${type.defaultIcon} ${type.displayName}');
              }).toList(),
            ),
            const SizedBox(height: 20),
            
            if (_selectedType != EventInfoBlockType.divider) ...[
              Text(_getContentLabel(), style: AppTypography.labelLarge),
              const SizedBox(height: 8),
              TextField(
                controller: _contentController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: _getContentHint(),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                maxLines: _selectedType == EventInfoBlockType.text ? 3 : 1,
                textInputAction: _needsSubContent() ? TextInputAction.next : TextInputAction.done,
                onSubmitted: _needsSubContent() ? null : (_) => _canSubmit() ? _submit() : null,
              ),
              
              if (_needsSubContent()) ...[
                const SizedBox(height: 16),
                Text(_getSubContentLabel(), style: AppTypography.labelLarge),
                const SizedBox(height: 8),
                TextField(
                  controller: _subContentController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: _getSubContentHint(),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  maxLines: 1,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _canSubmit() ? _submit() : null,
                ),
              ],
            ],
            
            const SizedBox(height: 16),
            
            // Hızlı ekleme modu checkbox
            Row(
              children: [
                Checkbox(
                  value: _keepAdding,
                  onChanged: (value) => setState(() => _keepAdding = value ?? false),
                  activeColor: AppColors.primary,
                ),
                GestureDetector(
                  onTap: () => setState(() => _keepAdding = !_keepAdding),
                  child: Text(
                    'Eklemeye devam et',
                    style: AppTypography.bodyMedium.copyWith(
                      color: _keepAdding ? AppColors.primary : AppColors.neutral600,
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: AppButton(
                text: _keepAdding ? 'Ekle ve Devam Et' : 'Ekle',
                icon: Icons.add,
                onPressed: _canSubmit() ? _submit : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeChip(EventInfoBlockType type, String label) {
    final isSelected = _selectedType == type;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.white : AppColors.neutral700,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _selectedType = type;
            // Chip değiştiğinde text field'ları temizle
            _contentController.clear();
            _subContentController.clear();
          });
        }
      },
      backgroundColor: AppColors.neutral200,
      selectedColor: AppColors.primary,
      disabledColor: AppColors.neutral300,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      labelPadding: const EdgeInsets.symmetric(horizontal: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected ? AppColors.primary : Colors.transparent,
          width: isSelected ? 2 : 0,
        ),
      ),
    );
  }

  String _getContentLabel() {
    switch (_selectedType) {
      case EventInfoBlockType.header:
        return 'Başlık';
      case EventInfoBlockType.subheader:
        return 'Alt Başlık';
      case EventInfoBlockType.scheduleItem:
        return 'Saat';
      case EventInfoBlockType.warning:
      case EventInfoBlockType.info:
      case EventInfoBlockType.tip:
        return 'Başlık';
      case EventInfoBlockType.quote:
        return 'Alıntı';
      default:
        return 'İçerik';
    }
  }

  String _getContentHint() {
    switch (_selectedType) {
      case EventInfoBlockType.header:
        return 'Örn: CUMARTESİ 04.04.2026';
      case EventInfoBlockType.subheader:
        return 'Örn: PAZAR YARIŞ GÜNÜ TCR PLANLAMASI';
      case EventInfoBlockType.scheduleItem:
        return 'Örn: 10:00-12:00';
      case EventInfoBlockType.warning:
        return 'Örn: ÖNEMLİ UYARI';
      case EventInfoBlockType.info:
        return 'Örn: Bilgilendirme';
      case EventInfoBlockType.tip:
        return 'Örn: İpucu';
      case EventInfoBlockType.quote:
        return 'Alıntı metni';
      default:
        return 'İçerik yazın...';
    }
  }

  String _getSubContentLabel() {
    switch (_selectedType) {
      case EventInfoBlockType.scheduleItem:
        return 'Açıklama';
      case EventInfoBlockType.warning:
      case EventInfoBlockType.info:
      case EventInfoBlockType.tip:
        return 'Detay';
      case EventInfoBlockType.quote:
        return 'Kaynak';
      default:
        return 'Ek Bilgi';
    }
  }

  String _getSubContentHint() {
    switch (_selectedType) {
      case EventInfoBlockType.scheduleItem:
        return 'Örn: Kit Dağıtımı';
      case EventInfoBlockType.warning:
        return 'Örn: Gruptan kopmamaya çalışın';
      case EventInfoBlockType.quote:
        return 'Örn: MEHMET TERZİ';
      default:
        return 'Ek bilgi yazın...';
    }
  }

  bool _needsSubContent() {
    return [
      EventInfoBlockType.scheduleItem,
      EventInfoBlockType.warning,
      EventInfoBlockType.info,
      EventInfoBlockType.tip,
      EventInfoBlockType.quote,
    ].contains(_selectedType);
  }

  bool _canSubmit() {
    if (_selectedType == EventInfoBlockType.divider) return true;
    return _contentController.text.trim().isNotEmpty;
  }

  void _submit() {
    widget.notifier.addBlock(
      _selectedType,
      _selectedType == EventInfoBlockType.divider ? '---' : _contentController.text.trim(),
      subContent: _subContentController.text.trim().isNotEmpty ? _subContentController.text.trim() : null,
    );

    setState(() {
      _addedCount++;
    });

    if (_keepAdding) {
      // Hızlı ekleme modunda - formu temizle, sheet'i açık tut
      _contentController.clear();
      _subContentController.clear();
      // Kullanıcıya feedback ver
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_selectedType.displayName} eklendi'),
          duration: const Duration(milliseconds: 800),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      // Tek ekleme modunda - sheet'i kapat
      Navigator.pop(context);
    }
  }
}

/// Toplu Ekleme Sheet
class _BulkAddSheet extends StatefulWidget {
  final EventInfoBlocksNotifier notifier;

  const _BulkAddSheet({required this.notifier});

  @override
  State<_BulkAddSheet> createState() => _BulkAddSheetState();
}

class _BulkAddSheetState extends State<_BulkAddSheet> {
  final _textController = TextEditingController();
  EventInfoBlockType _selectedType = EventInfoBlockType.scheduleItem;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Toplu Ekle', style: AppTypography.titleLarge),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Her satır ayrı bir blok olarak eklenecek',
              style: AppTypography.bodySmall.copyWith(color: AppColors.neutral500),
            ),
            const SizedBox(height: 16),
            
            Text('Blok Türü', style: AppTypography.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildTypeChip(EventInfoBlockType.scheduleItem, '🕐 Program'),
                _buildTypeChip(EventInfoBlockType.listItem, '• Liste'),
                _buildTypeChip(EventInfoBlockType.text, '📝 Metin'),
                _buildTypeChip(EventInfoBlockType.checklistItem, '☑️ Kontrol'),
              ],
            ),
            const SizedBox(height: 16),
            
            Text(
              _selectedType == EventInfoBlockType.scheduleItem 
                  ? 'Program Öğeleri (saat | açıklama formatında)' 
                  : 'İçerik (her satır bir blok)',
              style: AppTypography.labelLarge,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _textController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: _selectedType == EventInfoBlockType.scheduleItem
                    ? '10:00-12:00 | Kit Dağıtımı\n16:00-17:00 | Shake Out Run\n18:00-20:00 | Makarna İkramı'
                    : 'Satır 1\nSatır 2\nSatır 3',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              maxLines: 8,
              keyboardType: TextInputType.multiline,
            ),
            
            const SizedBox(height: 8),
            Text(
              '${_getLineCount()} satır algılandı',
              style: AppTypography.bodySmall.copyWith(
                color: _getLineCount() > 0 ? AppColors.success : AppColors.neutral500,
              ),
            ),
            
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: AppButton(
                text: 'Tümünü Ekle (${_getLineCount()} blok)',
                icon: Icons.playlist_add,
                onPressed: _getLineCount() > 0 ? _submitAll : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeChip(EventInfoBlockType type, String label) {
    final isSelected = _selectedType == type;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.white : AppColors.neutral700,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() => _selectedType = type);
        }
      },
      backgroundColor: AppColors.neutral200,
      selectedColor: AppColors.primary,
    );
  }

  int _getLineCount() {
    final text = _textController.text.trim();
    if (text.isEmpty) return 0;
    return text.split('\n').where((line) => line.trim().isNotEmpty).length;
  }

  void _submitAll() {
    final lines = _textController.text.trim().split('\n').where((line) => line.trim().isNotEmpty).toList();
    
    for (final line in lines) {
      if (_selectedType == EventInfoBlockType.scheduleItem && line.contains('|')) {
        // Saat | Açıklama formatı
        final parts = line.split('|');
        final time = parts[0].trim();
        final description = parts.length > 1 ? parts[1].trim() : '';
        widget.notifier.addBlock(_selectedType, time, subContent: description);
      } else {
        widget.notifier.addBlock(_selectedType, line.trim());
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${lines.length} blok eklendi!'),
        backgroundColor: AppColors.success,
      ),
    );
    
    Navigator.pop(context);
  }
}

/// Edit Block Bottom Sheet
class _EditBlockSheet extends StatefulWidget {
  final EventInfoBlockEntity block;
  final Function(EventInfoBlockEntity updatedBlock) onSave;

  const _EditBlockSheet({
    required this.block,
    required this.onSave,
  });

  @override
  State<_EditBlockSheet> createState() => _EditBlockSheetState();
}

class _EditBlockSheetState extends State<_EditBlockSheet> {
  late TextEditingController _contentController;
  late TextEditingController _subContentController;

  @override
  void initState() {
    super.initState();
    _contentController = TextEditingController(text: widget.block.content);
    _subContentController = TextEditingController(text: widget.block.subContent ?? '');
  }

  @override
  void dispose() {
    _contentController.dispose();
    _subContentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Bloğu Düzenle', style: AppTypography.titleLarge),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                widget.block.type.displayName,
                style: AppTypography.labelMedium.copyWith(color: AppColors.primary),
              ),
            ),
            const SizedBox(height: 20),
            
            if (widget.block.type != EventInfoBlockType.divider) ...[
              Text('İçerik', style: AppTypography.labelLarge),
              const SizedBox(height: 8),
              TextField(
                controller: _contentController,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                maxLines: widget.block.type == EventInfoBlockType.text ? 3 : 1,
              ),
              const SizedBox(height: 16),
              
              Text('Ek Bilgi (Opsiyonel)', style: AppTypography.labelLarge),
              const SizedBox(height: 8),
              TextField(
                controller: _subContentController,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                maxLines: 2,
              ),
            ],
            
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: AppButton(
                text: 'Kaydet',
                icon: Icons.save,
                onPressed: _save,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    final updatedBlock = EventInfoBlockEntity(
      id: widget.block.id,
      eventId: widget.block.eventId,
      type: widget.block.type,
      content: _contentController.text.trim(),
      subContent: _subContentController.text.trim().isNotEmpty 
          ? _subContentController.text.trim() 
          : null,
      color: widget.block.color,
      icon: widget.block.icon,
      orderIndex: widget.block.orderIndex,
      createdAt: widget.block.createdAt,
      updatedAt: DateTime.now(),
    );
    widget.onSave(updatedBlock);
  }
}
