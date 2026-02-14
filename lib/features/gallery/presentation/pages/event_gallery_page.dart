import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// Event Gallery Page
class EventGalleryPage extends ConsumerWidget {
  final String eventId;

  const EventGalleryPage({super.key, required this.eventId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fotoğraflar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_photo_alternate),
            onPressed: () {
              // Add photo
            },
          ),
        ],
      ),
      body: MasonryGridView.count(
        crossAxisCount: 3,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        padding: const EdgeInsets.all(4),
        itemCount: 20,
        itemBuilder: (context, index) {
          return _buildPhotoItem(context, index);
        },
      ),
    );
  }

  Widget _buildPhotoItem(BuildContext context, int index) {
    // Random height for masonry effect
    final heights = [150.0, 200.0, 180.0, 220.0, 160.0];
    final height = heights[index % heights.length];

    return GestureDetector(
      onTap: () => _openPhotoViewer(context, index),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: AppColors.neutral200,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Placeholder image
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                color: Color.lerp(
                  AppColors.primaryContainer,
                  AppColors.secondaryContainer,
                  index / 20,
                ),
                child: Center(
                  child: Icon(
                    Icons.photo,
                    size: 40,
                    color: AppColors.neutral400,
                  ),
                ),
              ),
            ),
            // Overlay for first image (showing count)
            if (index == 0)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.photo_library,
                        size: 14,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '20 fotoğraf',
                        style: AppTypography.labelSmall.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openPhotoViewer(BuildContext context, int initialIndex) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PhotoViewerPage(
          initialIndex: initialIndex,
          totalPhotos: 20,
        ),
      ),
    );
  }
}

/// Full Screen Photo Viewer
class PhotoViewerPage extends StatefulWidget {
  final int initialIndex;
  final int totalPhotos;

  const PhotoViewerPage({
    super.key,
    required this.initialIndex,
    required this.totalPhotos,
  });

  @override
  State<PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<PhotoViewerPage> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(
          '${_currentIndex + 1} / ${widget.totalPhotos}',
          style: AppTypography.titleMedium.copyWith(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () {
              // Download photo
            },
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              // Share photo
            },
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {
              // More options
            },
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() => _currentIndex = index);
        },
        itemCount: widget.totalPhotos,
        itemBuilder: (context, index) {
          return Center(
            child: Container(
              color: Color.lerp(
                AppColors.primaryContainer,
                AppColors.secondaryContainer,
                index / widget.totalPhotos,
              ),
              child: const Center(
                child: Icon(
                  Icons.photo,
                  size: 100,
                  color: AppColors.neutral400,
                ),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.favorite_border, color: Colors.white),
                onPressed: () {},
              ),
              const SizedBox(width: 32),
              IconButton(
                icon: const Icon(Icons.comment_outlined, color: Colors.white),
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );
  }
}
