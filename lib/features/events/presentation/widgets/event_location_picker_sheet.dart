import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../routes/presentation/widgets/route_location_picker.dart';

/// Etkinlik için haritadan konum seçimi (antrenman/yarış dışı etkinlikler)
/// Popup'ta harita açılır, kullanıcı nokta seçer ve isteğe bağlı konum adı girer.
class EventLocationPickerSheet extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;
  final String? initialName;

  const EventLocationPickerSheet({
    super.key,
    this.initialLat,
    this.initialLng,
    this.initialName,
  });

  /// Bottom sheet açar; seçim yapılırsa (lat, lng, name?) döner.
  static Future<({double lat, double lng, String? name})?> show(
    BuildContext context, {
    double? initialLat,
    double? initialLng,
    String? initialName,
  }) async {
    final result = await showModalBottomSheet<({double lat, double lng, String? name})>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: EventLocationPickerSheet(
          initialLat: initialLat,
          initialLng: initialLng,
          initialName: initialName,
        ),
      ),
    );
    return result;
  }

  @override
  State<EventLocationPickerSheet> createState() => _EventLocationPickerSheetState();
}

class _EventLocationPickerSheetState extends State<EventLocationPickerSheet> {
  double? _lat;
  double? _lng;
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _lat = widget.initialLat;
    _lng = widget.initialLng;
    _nameController = TextEditingController(text: widget.initialName ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.neutral300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Konum seçin',
                style: AppTypography.titleLarge.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Haritada buluşma noktasına dokunun. İsteğe bağlı olarak mekan adı yazın (örn. kafe adı).',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.neutral500,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: AppTextField(
                controller: _nameController,
                label: 'Konum adı (isteğe bağlı)',
                hint: 'Örn. Kafe XYZ, Toplanma Noktası',
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: RouteLocationPicker(
                selectedLat: _lat,
                selectedLng: _lng,
                height: 280,
                showLabel: false,
                onLocationSelected: (lat, lng) {
                  setState(() {
                    _lat = lat;
                    _lng = lng;
                  });
                },
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: AppButton(
                      text: 'İptal',
                      variant: AppButtonVariant.outlined,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppButton(
                      text: 'Seç',
                      onPressed: (_lat != null && _lng != null)
                          ? () {
                              Navigator.of(context).pop((
                                lat: _lat!,
                                lng: _lng!,
                                name: _nameController.text.trim().isEmpty
                                    ? null
                                    : _nameController.text.trim(),
                              ));
                            }
                          : null,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
