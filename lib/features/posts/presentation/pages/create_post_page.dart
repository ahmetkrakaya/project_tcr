import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../domain/entities/post_block_entity.dart';
import '../providers/post_provider.dart';
import 'dart:io' if (dart.library.html) 'dart:io';

import '../../data/models/post_block_model.dart';
import '../../data/models/post_model.dart';

/// XFile'dan hem web hem mobil uyumlu Image widget'ı oluşturur.
Widget _buildXFileImage(XFile xFile, {BoxFit? fit, double? width, double? height}) {
  if (kIsWeb) {
    // Web'de XFile.path blob URL döner, Image.network ile gösterebiliriz
    return Image.network(xFile.path, fit: fit, width: width, height: height);
  } else {
    return Image.file(File(xFile.path), fit: fit, width: width, height: height);
  }
}

/// Create/Edit Post Page
class CreatePostPage extends ConsumerStatefulWidget {
  final String? postId;

  const CreatePostPage({super.key, this.postId});

  @override
  ConsumerState<CreatePostPage> createState() => _CreatePostPageState();
}

class _CreatePostPageState extends ConsumerState<CreatePostPage> {
  final _titleController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String? _coverImageUrl;
  XFile? _coverImageFile;
  List<PostBlockModel> _blocks = [];
  /// Blok indeksine göre bekleyen görsel dosyaları (post kaydedilince yüklenecek)
  final Map<String, XFile> _pendingBlockImages = {};
  final List<String?> _blockPendingImageKeys = [];
  bool _isLoading = false;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    if (widget.postId != null) {
      _isEditing = true;
      _loadPostData();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _loadPostData() async {
    try {
      final post = await ref.read(postByIdProvider(widget.postId!).future);
      final blocks = await ref.read(postBlocksProvider(widget.postId!).future);
      
      setState(() {
        _titleController.text = post.title;
        _coverImageUrl = post.coverImageUrl;
        _blocks = blocks.map((b) => PostBlockModel.fromEntity(b)).toList();
        _blockPendingImageKeys.clear();
        _blockPendingImageKeys.addAll(List.filled(_blocks.length, null));
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Post yüklenemedi: $e')),
        );
      }
    }
  }

  Future<void> _pickCoverImage() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        setState(() {
          _coverImageFile = pickedFile;
          // URL'i temizle; kaydedilince yüklenecek
          _coverImageUrl = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fotoğraf seçilemedi: $e')),
        );
      }
    }
  }

  /// Kapak görselini Supabase'e yükler; post kaydedilirken çağrılır.
  Future<String?> _uploadCoverImageIfNeeded() async {
    if (_coverImageFile == null) return _coverImageUrl;
    final supabase = Supabase.instance.client;
    final fileName = 'post_cover_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final bytes = await _coverImageFile!.readAsBytes();
    await supabase.storage.from('post-images').uploadBinary(
      fileName,
      bytes,
      fileOptions: const FileOptions(contentType: 'image/jpeg'),
    );
    return supabase.storage.from('post-images').getPublicUrl(fileName);
  }

  Future<void> _savePost() async {
    if (!_formKey.currentState!.validate()) return;

    // Async işlemler sonrasında context kullanmamak için referansları başta al
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    setState(() => _isLoading = true);

    try {
      final dataSource = ref.read(postDataSourceProvider);
      final supabase = Supabase.instance.client;

      // Kapak görseli: sadece post kaydedilirken yükle
      String? coverUrlToUse = _coverImageUrl;
      if (_coverImageFile != null) {
        coverUrlToUse = await _uploadCoverImageIfNeeded();
      }

      // Blok görselleri: bekleyen dosyaları post kaydedilirken yükle
      final List<PostBlockModel> blocksToSave = [];
      for (int i = 0; i < _blocks.length; i++) {
        PostBlockModel block = _blocks[i];
        final pendingKey = i < _blockPendingImageKeys.length ? _blockPendingImageKeys[i] : null;
        if (block.type == 'image' && pendingKey != null && _pendingBlockImages.containsKey(pendingKey)) {
          final xFile = _pendingBlockImages[pendingKey]!;
          final fileName = 'post_block_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
          final blockBytes = await xFile.readAsBytes();
          await supabase.storage.from('post-images').uploadBinary(
            fileName,
            blockBytes,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          );
          final publicUrl = supabase.storage.from('post-images').getPublicUrl(fileName);
          block = block.copyWith(imageUrl: publicUrl);
        }
        blocksToSave.add(block);
      }

      if (_isEditing && widget.postId != null) {
        // Get current post to preserve userId
        final currentPost = await ref.read(postByIdProvider(widget.postId!).future);
        
        // Update existing post (pin bilgisini koru)
        final postModel = PostModel(
          id: widget.postId!,
          userId: currentPost.userId, // Preserve original userId
          title: _titleController.text.trim(),
          coverImageUrl: coverUrlToUse,
          isPublished: true,
          blocks: blocksToSave,
          createdAt: currentPost.createdAt, // Preserve original createdAt
          isPinned: currentPost.isPinned,
          pinnedAt: currentPost.pinnedAt,
        );

        await dataSource.updatePost(postModel);
        
        // Update blocks
        // First delete all existing blocks
        await dataSource.deleteAllPostBlocks(widget.postId!);
        
        // Then create new blocks
        for (int i = 0; i < blocksToSave.length; i++) {
          final block = blocksToSave[i].copyWith(
            postId: widget.postId!,
            orderIndex: i,
          );
          await dataSource.createPostBlock(block);
        }

        ref.invalidate(postByIdProvider(widget.postId!));
        ref.invalidate(postBlocksProvider(widget.postId!));
        final updated = await dataSource.getPostById(widget.postId!);
        ref.read(postsProvider.notifier).replacePost(updated.toEntity());

        if (!mounted) return;

        router.pop();
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Post başarıyla güncellendi!'),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        // Create new post
        final createState = ref.read(createPostProvider.notifier);
        
        await createState.createPost(
          title: _titleController.text.trim(),
          coverImageUrl: coverUrlToUse,
          blocks: blocksToSave,
        );

        final result = ref.read(createPostProvider);
        result.when(
          data: (post) {
            if (post != null) {
              ref.read(postsProvider.notifier).addPost(post);

              if (!mounted) return;

              router.pop();
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('Post başarıyla oluşturuldu!'),
                  backgroundColor: AppColors.success,
                ),
              );
            }
          },
          loading: () {},
          error: (error, _) {
            if (mounted) {
              messenger.showSnackBar(
                SnackBar(content: Text('Hata: $error')),
              );
            }
          },
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showAddBlockDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _AddBlockSheet(
        onBlockSelected: (type) {
          _showBlockEditor(type);
        },
      ),
    );
  }

  void _showBlockEditor(PostBlockType type) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: SingleChildScrollView(
          child: _BlockEditorSheet(
            type: type,
            onBack: () => _showAddBlockDialog(),
            onSave: (block, {XFile? pendingImageFile}) {
              setState(() {
                _blocks.add(block);
                String? key;
                if (pendingImageFile != null) {
                  key = 'block_${DateTime.now().millisecondsSinceEpoch}';
                  _pendingBlockImages[key] = pendingImageFile;
                }
                _blockPendingImageKeys.add(key);
              });
              Navigator.pop(context);
            },
          ),
        ),
      ),
    );
  }

  void _editBlock(int index, PostBlockModel block) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: SingleChildScrollView(
          child: _BlockEditorSheet(
            type: PostBlockType.fromString(block.type),
            initialBlock: block,
            onSave: (updatedBlock, {XFile? pendingImageFile}) {
              setState(() {
                _blocks[index] = updatedBlock;
                if (pendingImageFile != null) {
                  final key = 'block_${DateTime.now().millisecondsSinceEpoch}';
                  _pendingBlockImages[key] = pendingImageFile;
                  _blockPendingImageKeys[index] = key;
                } else {
                  _blockPendingImageKeys[index] = null;
                }
              });
              Navigator.pop(context);
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Postu Düzenle' : 'Yeni Post Oluştur'),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _savePost,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    TextFormField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'Başlık',
                        hintText: 'Post başlığını girin',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Başlık gereklidir';
                        }
                        return null;
                      },
                      maxLength: 200,
                    ),
                    const SizedBox(height: 24),

                    // Cover Image
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Kapak Görseli',
                          style: AppTypography.titleMedium,
                        ),
                        if (_coverImageUrl != null || _coverImageFile != null)
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _coverImageUrl = null;
                                _coverImageFile = null;
                              });
                            },
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: const Text('Sil'),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.error,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: _pickCoverImage,
                      child: _coverImageFile != null
                          ? Container(
                              height: 200,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.neutral300),
                              ),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: _buildXFileImage(
                                      _coverImageFile!,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      height: double.infinity,
                                    ),
                                  ),
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.6),
                                        shape: BoxShape.circle,
                                      ),
                                      child: IconButton(
                                        icon: const Icon(Icons.close, color: Colors.white),
                                        onPressed: () {
                                          setState(() {
                                            _coverImageFile = null;
                                          });
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : _coverImageUrl != null
                              ? Container(
                                  height: 200,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AppColors.neutral300),
                                  ),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: Image.network(
                                          _coverImageUrl!,
                                          fit: BoxFit.fill,
                                          width: double.infinity,
                                          height: double.infinity,
                                          errorBuilder: (_, __, ___) => const Icon(Icons.image, size: 48),
                                        ),
                                      ),
                                      Positioned(
                                        top: 8,
                                        right: 8,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: Colors.black.withValues(alpha: 0.6),
                                            shape: BoxShape.circle,
                                          ),
                                          child: IconButton(
                                            icon: const Icon(Icons.close, color: Colors.white),
                                            onPressed: () {
                                              setState(() {
                                                _coverImageUrl = null;
                                              });
                                            },
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : AppCard(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.add_photo_alternate,
                                          size: 40,
                                          color: AppColors.neutral400,
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                'Kapak görseli ekle',
                                                style: AppTypography.bodyMedium.copyWith(
                                                  color: AppColors.neutral600,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Tıklayarak görsel seçin',
                                                style: AppTypography.bodySmall.copyWith(
                                                  color: AppColors.neutral400,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                    ),
                    const SizedBox(height: 24),

                    // Blocks Section Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'İçerik Blokları',
                          style: AppTypography.titleMedium,
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: _showAddBlockDialog,
                          color: AppColors.primary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),

            // Blocks List
            if (_blocks.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: AppCard(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Icon(Icons.article_outlined, size: 48, color: AppColors.neutral400),
                          const SizedBox(height: 12),
                          Text(
                            'Henüz içerik bloğu eklenmedi',
                            style: AppTypography.bodyMedium.copyWith(
                              color: AppColors.neutral500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Yukarıdaki + butonuna tıklayarak blok ekleyebilirsiniz',
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.neutral400,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverReorderableList(
                  itemCount: _blocks.length,
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (newIndex > oldIndex) {
                        newIndex -= 1;
                      }
                      final item = _blocks.removeAt(oldIndex);
                      final key = _blockPendingImageKeys.removeAt(oldIndex);
                      _blocks.insert(newIndex, item);
                      _blockPendingImageKeys.insert(newIndex, key);
                      for (int i = 0; i < _blocks.length; i++) {
                        _blocks[i] = _blocks[i].copyWith(orderIndex: i);
                      }
                    });
                  },
                  itemBuilder: (context, index) {
                    final block = _blocks[index];
                    return _buildBlockCard(block, index);
                  },
                ),
              ),

            // Bottom spacing
            const SliverToBoxAdapter(
              child: SizedBox(height: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockCard(PostBlockModel block, int index) {
    return AppCard(
      key: ValueKey(block.id.isNotEmpty ? block.id : 'block_$index'),
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ReorderableDragStartListener(
              index: index,
              child: Icon(
                Icons.drag_handle,
                color: AppColors.neutral400,
                size: 20,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              _getBlockIcon(PostBlockType.fromString(block.type)),
              color: AppColors.primary,
            ),
          ],
        ),
        title: Text(
          PostBlockType.fromString(block.type).displayName,
          style: AppTypography.titleSmall,
        ),
        subtitle: Text(
          block.content,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodySmall,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, size: 20),
              onPressed: () {
                _editBlock(index, block);
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete, size: 20),
              onPressed: () {
                setState(() {
                  final key = index < _blockPendingImageKeys.length ? _blockPendingImageKeys[index] : null;
                  if (key != null) _pendingBlockImages.remove(key);
                  _blocks.removeAt(index);
                  _blockPendingImageKeys.removeAt(index);
                  for (int i = 0; i < _blocks.length; i++) {
                    _blocks[i] = _blocks[i].copyWith(orderIndex: i);
                  }
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  IconData _getBlockIcon(PostBlockType type) {
    switch (type) {
      case PostBlockType.header:
        return Icons.title;
      case PostBlockType.subheader:
        return Icons.subtitles;
      case PostBlockType.scheduleItem:
        return Icons.schedule;
      case PostBlockType.warning:
        return Icons.warning;
      case PostBlockType.info:
        return Icons.info;
      case PostBlockType.tip:
        return Icons.lightbulb;
      case PostBlockType.text:
        return Icons.text_fields;
      case PostBlockType.quote:
        return Icons.format_quote;
      case PostBlockType.listItem:
        return Icons.list;
      case PostBlockType.checklistItem:
        return Icons.checklist;
      case PostBlockType.divider:
        return Icons.horizontal_rule;
      case PostBlockType.image:
        return Icons.image;
      case PostBlockType.raceResults:
        return Icons.emoji_events;
    }
  }
}

/// Add Block Type Selector
class _AddBlockSheet extends StatelessWidget {
  final Function(PostBlockType) onBlockSelected;

  const _AddBlockSheet({required this.onBlockSelected});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Blok Türü Seç',
                style: AppTypography.titleLarge,
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: PostBlockType.values
                      .where((type) => type != PostBlockType.raceResults) // raceResults sadece otomatik oluşturulur
                      .map((type) {
                    return _buildBlockTypeCard(context, type);
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockTypeCard(BuildContext context, PostBlockType type) {
    return InkWell(
      onTap: () {
        Navigator.pop(context); // Close block type selector first
        onBlockSelected(type); // Then show block editor
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: (MediaQuery.of(context).size.width - 64) / 3,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.neutral100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.neutral300),
        ),
        child: Column(
          children: [
            Text(
              type.defaultIcon,
              style: const TextStyle(fontSize: 32),
            ),
            const SizedBox(height: 8),
            Text(
              type.displayName,
              style: AppTypography.labelMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Block Editor Sheet
class _BlockEditorSheet extends StatefulWidget {
  final PostBlockType type;
  final void Function(PostBlockModel block, {XFile? pendingImageFile}) onSave;
  final PostBlockModel? initialBlock;
  /// Geri butonu ile blok türü seçimine dönmek için (yeni blok eklerken)
  final VoidCallback? onBack;

  const _BlockEditorSheet({
    required this.type,
    required this.onSave,
    this.initialBlock,
    this.onBack,
  });

  @override
  State<_BlockEditorSheet> createState() => _BlockEditorSheetState();
}

class _BlockEditorSheetState extends State<_BlockEditorSheet> {
  final _contentController = TextEditingController();
  final _subContentController = TextEditingController();
  XFile? _selectedImage;
  String? _imageUrl;

  @override
  void initState() {
    super.initState();
    if (widget.initialBlock != null) {
      _contentController.text = widget.initialBlock!.content;
      _subContentController.text = widget.initialBlock!.subContent ?? '';
      _imageUrl = widget.initialBlock!.imageUrl;
    }
  }

  @override
  void dispose() {
    _contentController.dispose();
    _subContentController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        setState(() {
          _selectedImage = pickedFile;
          // Post kaydedilince yüklenecek; şimdi sadece seç
          _imageUrl = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fotoğraf seçilemedi: $e')),
        );
      }
    }
  }

  void _save() {
    // Görsel blokları: URL veya seçilmiş dosya gerekli (post kaydedilince yüklenecek)
    if (widget.type == PostBlockType.image) {
      if (_imageUrl == null && _selectedImage == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lütfen bir görsel seçin')),
        );
        return;
      }
    } else if (_contentController.text.trim().isEmpty && widget.type != PostBlockType.divider) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('İçerik boş olamaz')),
      );
      return;
    }

    final block = PostBlockModel(
      id: widget.initialBlock?.id ?? '',
      postId: widget.initialBlock?.postId ?? '',
      type: widget.type.toDbString(),
      content: widget.type == PostBlockType.image
          ? 'Görsel'
          : (_contentController.text.trim().isEmpty 
              ? '---' 
              : _contentController.text.trim()),
      subContent: _subContentController.text.trim().isEmpty
          ? null
          : _subContentController.text.trim(),
      imageUrl: widget.type == PostBlockType.image
          ? (_selectedImage == null ? _imageUrl : null)
          : null,
      orderIndex: widget.initialBlock?.orderIndex ?? 0,
      createdAt: widget.initialBlock?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    widget.onSave(block, pendingImageFile: widget.type == PostBlockType.image ? _selectedImage : null);
    // Navigator.pop is called in onSave callback
  }

  @override
  Widget build(BuildContext context) {
    final isScheduleItem = widget.type == PostBlockType.scheduleItem;
    final isImageBlock = widget.type == PostBlockType.image;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (widget.onBack != null) ...[
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onBack!();
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    widget.initialBlock != null
                        ? '${widget.type.displayName} Düzenle'
                        : '${widget.type.displayName} Ekle',
                    style: AppTypography.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (isImageBlock) ...[
              // Görsel seçimi (post kaydedilince yüklenecek) – yatay kart
              GestureDetector(
                onTap: _pickImage,
                child: _selectedImage != null
                    ? Container(
                        height: 200,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.neutral300),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: _buildXFileImage(
                            _selectedImage!,
                            fit: BoxFit.cover,
                          ),
                        ),
                      )
                    : _imageUrl != null
                        ? Container(
                            height: 200,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.neutral300),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                _imageUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(Icons.image, size: 48),
                              ),
                            ),
                          )
                        : AppCard(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.add_photo_alternate,
                                    size: 40,
                                    color: AppColors.neutral400,
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'Görsel seç',
                                          style: AppTypography.bodyMedium.copyWith(
                                            color: AppColors.neutral600,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Tıklayarak görsel seçin',
                                          style: AppTypography.bodySmall.copyWith(
                                            color: AppColors.neutral400,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
              ),
              const SizedBox(height: 16),
              // Optional caption
              TextFormField(
                controller: _contentController,
                decoration: const InputDecoration(
                  labelText: 'Alt Yazı (opsiyonel)',
                  hintText: 'Görsel için açıklama',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ] else if (isScheduleItem) ...[
              TextFormField(
                controller: _contentController,
                decoration: const InputDecoration(
                  labelText: 'Saat',
                  hintText: 'Örn: 10:00-12:00',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _subContentController,
                decoration: const InputDecoration(
                  labelText: 'Açıklama',
                  hintText: 'Örn: Kit Dağıtımı',
                  border: OutlineInputBorder(),
                ),
              ),
            ] else ...[
              TextFormField(
                controller: _contentController,
                decoration: InputDecoration(
                  labelText: widget.type == PostBlockType.divider
                      ? 'Ayırıcı (opsiyonel)'
                      : 'İçerik',
                  hintText: widget.type == PostBlockType.divider
                      ? '---'
                      : 'İçeriği girin',
                  border: const OutlineInputBorder(),
                ),
                maxLines: widget.type == PostBlockType.text ? 5 : 1,
              ),
              if (widget.type == PostBlockType.header ||
                  widget.type == PostBlockType.subheader) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _subContentController,
                  decoration: const InputDecoration(
                    labelText: 'Alt Başlık (opsiyonel)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ],
            const SizedBox(height: 24),
            AppButton(
              text: widget.initialBlock != null ? 'Güncelle' : 'Ekle',
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}
