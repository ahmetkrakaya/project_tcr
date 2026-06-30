import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../utils/logo_brand_color_extractor.dart';

/// Marka rengi seçimi için palet bottom sheet.
class BrandColorPickerSheet extends StatelessWidget {
  const BrandColorPickerSheet({
    super.key,
    required this.initialColor,
    this.logoSuggestedColor,
  });

  final Color initialColor;
  final Color? logoSuggestedColor;

  static const _palette = [
    Color(0xFF1B4332),
    Color(0xFF2D6A4F),
    Color(0xFF40916C),
    Color(0xFF006466),
    Color(0xFF005F73),
    Color(0xFF0A9396),
    Color(0xFF1D3557),
    Color(0xFF264653),
    Color(0xFF023047),
    Color(0xFF03045E),
    Color(0xFF0077B6),
    Color(0xFF0096C7),
    Color(0xFF6A040F),
    Color(0xFF9D0208),
    Color(0xFFD00000),
    Color(0xFFDC2F02),
    Color(0xFFE85D04),
    Color(0xFFF48C06),
    Color(0xFF370617),
    Color(0xFF6A0572),
    Color(0xFF7209B7),
    Color(0xFF560BAD),
    Color(0xFF3C096C),
    Color(0xFF240046),
    Color(0xFF2B2D42),
    Color(0xFF343A40),
    Color(0xFF495057),
    Color(0xFF212529),
    Color(0xFFBC6C25),
    Color(0xFF606C38),
    Color(0xFF283618),
    Color(0xFF386641),
  ];

  static Future<Color?> show(
    BuildContext context, {
    required Color initialColor,
    Color? logoSuggestedColor,
  }) {
    return showModalBottomSheet<Color>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => BrandColorPickerSheet(
        initialColor: initialColor,
        logoSuggestedColor: logoSuggestedColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = ValueNotifier<Color>(initialColor);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.neutral300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Marka rengi seç',
            style: AppTypography.titleMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<Color>(
            valueListenable: selected,
            builder: (context, color, _) {
              return Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.neutral300),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      colorToHex(color),
                      style: AppTypography.titleSmall.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, color),
                    child: const Text('Seç'),
                  ),
                ],
              );
            },
          ),
          if (logoSuggestedColor != null) ...[
            const SizedBox(height: 16),
            Text(
              'Logodan önerilen',
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.neutral500,
              ),
            ),
            const SizedBox(height: 8),
            _ColorChip(
              color: logoSuggestedColor!,
              label: colorToHex(logoSuggestedColor!),
              isSelected: false,
              onTap: () => selected.value = logoSuggestedColor!,
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Palet',
            style: AppTypography.labelMedium.copyWith(
              color: AppColors.neutral500,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: ValueListenableBuilder<Color>(
                valueListenable: selected,
                builder: (context, current, _) {
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _palette.map((color) {
                      final isSelected = color.toARGB32() == current.toARGB32();
                      return _ColorChip(
                        color: color,
                        isSelected: isSelected,
                        onTap: () => selected.value = color,
                      );
                    }).toList(),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }
}

class _ColorChip extends StatelessWidget {
  const _ColorChip({
    required this.color,
    required this.onTap,
    required this.isSelected,
    this.label,
  });

  final Color color;
  final VoidCallback onTap;
  final bool isSelected;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: label != null ? 40 : 36,
            height: label != null ? 40 : 36,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? AppColors.primary : AppColors.neutral300,
                width: isSelected ? 3 : 1,
              ),
            ),
            child: isSelected
                ? Icon(
                    Icons.check,
                    color: _contrastIconColor(color),
                    size: 18,
                  )
                : null,
          ),
          if (label != null) ...[
            const SizedBox(width: 8),
            Text(label!, style: AppTypography.bodySmall),
          ],
        ],
      ),
    );
  }

  Color _contrastIconColor(Color bg) {
    final luminance = bg.computeLuminance();
    return luminance > 0.5 ? Colors.black87 : Colors.white;
  }
}
