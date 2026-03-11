import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../domain/entities/foundation_entity.dart';
import '../providers/foundation_provider.dart';

class FoundationsPage extends ConsumerStatefulWidget {
  const FoundationsPage({super.key});

  @override
  ConsumerState<FoundationsPage> createState() => _FoundationsPageState();
}

class _FoundationsPageState extends ConsumerState<FoundationsPage> {
  @override
  Widget build(BuildContext context) {
    final foundationsAsync = ref.watch(foundationsProvider);
    final isAdmin = ref.watch(isAdminProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vakıflar'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Vakıf Ekle',
              onPressed: () => _showAddDialog(context),
            ),
        ],
      ),
      body: foundationsAsync.when(
        data: (foundations) {
          if (foundations.isEmpty) {
            return EmptyStateWidget(
              icon: Icons.favorite_outline,
              title: 'Henüz vakıf yok',
              description: isAdmin
                  ? 'Vakıf eklemek için + butonuna basın'
                  : 'Vakıflar admin tarafından eklenir',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: foundations.length,
            itemBuilder: (context, index) {
              final f = foundations[index];
              return _FoundationCard(
                foundation: f,
                isAdmin: isAdmin,
                onEdit: () => _showEditDialog(context, f),
                onDelete: () => _showDeleteDialog(context, f),
              );
            },
          );
        },
        loading: () => const Center(child: LoadingWidget()),
        error: (error, _) => Center(
          child: ErrorStateWidget(
            title: 'Vakıflar yüklenemedi',
            message: error.toString(),
            onRetry: () => ref.invalidate(foundationsProvider),
          ),
        ),
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vakıf Ekle'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Vakıf / Kuruluş Adı',
            hintText: 'ör: LÖSEV',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              final success = await ref
                  .read(foundationCreationProvider.notifier)
                  .createFoundation(name);
              if (mounted) {
                final msg = success
                    ? 'Vakıf eklendi'
                    : _foundationError(ref.read(foundationCreationProvider));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(msg),
                    backgroundColor: success ? AppColors.success : AppColors.error,
                  ),
                );
              }
            },
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context, FoundationEntity foundation) {
    final controller = TextEditingController(text: foundation.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vakıf Düzenle'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Vakıf / Kuruluş Adı',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              final success = await ref
                  .read(foundationUpdateProvider.notifier)
                  .updateFoundation(foundation.id, name);
              if (mounted) {
                final msg = success
                    ? 'Vakıf güncellendi'
                    : _foundationError(ref.read(foundationUpdateProvider));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(msg),
                    backgroundColor: success ? AppColors.success : AppColors.error,
                  ),
                );
              }
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDeleteDialog(BuildContext context, FoundationEntity foundation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vakıfı Sil'),
        content: Text(
          '"${foundation.name}" vakfını silmek istediğinizden emin misiniz? '
          'Bu vakfa ait bağış kayıtları varsa silme işlemi yapılamaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Sil',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final success = await ref
        .read(foundationDeleteProvider.notifier)
        .deleteFoundation(foundation.id);

    if (mounted) {
      final msg = success
          ? 'Vakıf silindi'
          : _foundationError(ref.read(foundationDeleteProvider));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: success ? AppColors.success : AppColors.error,
        ),
      );
    }
  }

  String _foundationError(AsyncValue<void> state) {
    final e = state.error;
    if (e is PostgrestException) {
      if (e.code == '23505') return 'Bu isimde bir vakıf zaten var';
      if (e.code == '23503') return 'Bu vakfa ait bağış kayıtları var, silinemez';
    }
    return 'İşlem sırasında hata oluştu';
  }
}

class _FoundationCard extends StatelessWidget {
  final FoundationEntity foundation;
  final bool isAdmin;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _FoundationCard({
    required this.foundation,
    required this.isAdmin,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          Icons.favorite,
          color: AppColors.error.withValues(alpha: 0.7),
        ),
        title: Text(
          foundation.name,
          style: AppTypography.titleSmall.copyWith(fontWeight: FontWeight.w600),
        ),
        trailing: isAdmin
            ? PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 20),
                        SizedBox(width: 12),
                        Text('Düzenle'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, size: 20, color: AppColors.error),
                        SizedBox(width: 12),
                        Text('Sil', style: TextStyle(color: AppColors.error)),
                      ],
                    ),
                  ),
                ],
              )
            : null,
      ),
    );
  }
}
