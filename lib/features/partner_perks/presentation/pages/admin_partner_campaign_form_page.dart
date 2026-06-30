import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../../core/services/nominatim_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../../events/presentation/widgets/event_location_picker_sheet.dart';
import '../../data/models/partner_campaign_model.dart';
import '../../utils/logo_brand_color_extractor.dart';
import '../providers/partner_campaign_provider.dart';
import '../widgets/brand_color_picker_sheet.dart';

class AdminPartnerCampaignFormPage extends ConsumerStatefulWidget {
  const AdminPartnerCampaignFormPage({super.key, this.campaignId});

  final String? campaignId;

  bool get isEditing => campaignId != null;

  @override
  ConsumerState<AdminPartnerCampaignFormPage> createState() =>
      _AdminPartnerCampaignFormPageState();
}

class _AdminPartnerCampaignFormPageState
    extends ConsumerState<AdminPartnerCampaignFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _slugController;
  late final TextEditingController _partnerNameController;
  late final TextEditingController _taglineController;
  late final TextEditingController _brandColorController;
  late final TextEditingController _discountPercentController;
  late final TextEditingController _discountLabelController;
  late final TextEditingController _termsController;
  late final TextEditingController _redemptionHintController;
  late final TextEditingController _locationNameController;
  late final TextEditingController _locationAddressController;
  late final TextEditingController _sortOrderController;
  late final TextEditingController _usageLimitCountController;
  late final TextEditingController _successMessageController;

  bool _isActive = true;
  bool _qrRedemptionEnabled = false;
  String _usageLimitType = 'once_per_day';
  DateTime? _startsAt;
  DateTime? _endsAt;
  bool _hasEndsAt = false;
  bool _isSaving = false;
  bool _isExtractingColor = false;
  bool _sortOrderUserEdited = false;
  bool _defaultSortOrderApplied = false;
  String? _initializedCampaignKey;
  Uint8List? _localLogoBytes;
  String? _existingLogoUrl;
  Color? _logoSuggestedColor;
  double? _locationLat;
  double? _locationLng;

  @override
  void initState() {
    super.initState();
    _slugController = TextEditingController();
    _partnerNameController = TextEditingController();
    _taglineController = TextEditingController();
    _brandColorController = TextEditingController(text: '#1B4332');
    _discountPercentController = TextEditingController(text: '10');
    _discountLabelController = TextEditingController();
    _termsController = TextEditingController();
    _redemptionHintController = TextEditingController();
    _locationNameController = TextEditingController();
    _locationAddressController = TextEditingController();
    _sortOrderController = TextEditingController();
    _usageLimitCountController = TextEditingController(text: '1');
    _successMessageController = TextEditingController();
    _startsAt = DateTime.now();
  }

  @override
  void dispose() {
    _slugController.dispose();
    _partnerNameController.dispose();
    _taglineController.dispose();
    _brandColorController.dispose();
    _discountPercentController.dispose();
    _discountLabelController.dispose();
    _termsController.dispose();
    _redemptionHintController.dispose();
    _locationNameController.dispose();
    _locationAddressController.dispose();
    _sortOrderController.dispose();
    _usageLimitCountController.dispose();
    _successMessageController.dispose();
    super.dispose();
  }

  void _initFromCampaign(PartnerCampaignModel campaign) {
    final key =
        '${campaign.id}:${campaign.updatedAt?.millisecondsSinceEpoch ?? 0}';
    if (_initializedCampaignKey == key) return;

    _initializedCampaignKey = key;
    _localLogoBytes = null;
    _slugController.text = campaign.slug;
    _partnerNameController.text = campaign.partnerName;
    _taglineController.text = campaign.tagline ?? '';
    _brandColorController.text = campaign.brandColor;
    _discountPercentController.text = campaign.discountPercent.toString();
    _discountLabelController.text = campaign.discountLabel;
    _termsController.text = campaign.terms ?? '';
    _redemptionHintController.text = campaign.redemptionHint;
    _locationNameController.text = campaign.locationName ?? '';
    _locationAddressController.text = campaign.locationAddress ?? '';
    _locationLat = campaign.locationLat;
    _locationLng = campaign.locationLng;
    _sortOrderController.text = campaign.sortOrder.toString();
    _isActive = campaign.isActive;
    _qrRedemptionEnabled = campaign.qrRedemptionEnabled;
    _usageLimitType = campaign.usageLimitType;
    _usageLimitCountController.text =
        (campaign.usageLimitCount ?? 1).toString();
    _successMessageController.text = campaign.successMessage ?? '';
    _startsAt = campaign.startsAt;
    _endsAt = campaign.endsAt;
    _hasEndsAt = campaign.endsAt != null;
    _existingLogoUrl = campaign.logoUrl;
    _loadLogoSuggestedColor();
  }

  void _scheduleDefaultSortOrder(List<PartnerCampaignModel> campaigns) {
    if (widget.isEditing || _sortOrderUserEdited || _defaultSortOrderApplied) {
      return;
    }

    _defaultSortOrderApplied = true;
    final nextOrder = campaigns.where((campaign) => campaign.isActive).length;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.isEditing || _sortOrderUserEdited) return;
      if (_sortOrderController.text == nextOrder.toString()) return;
      setState(() => _sortOrderController.text = nextOrder.toString());
    });
  }

  Future<Uint8List?> _currentLogoBytes() async {
    if (_localLogoBytes != null) return _localLogoBytes;
    if (_existingLogoUrl == null || _existingLogoUrl!.isEmpty) return null;

    try {
      final response = await Dio().get<List<int>>(
        _existingLogoUrl!,
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      if (data == null || data.isEmpty) return null;
      return Uint8List.fromList(data);
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadLogoSuggestedColor() async {
    final bytes = await _currentLogoBytes();
    if (bytes == null || !mounted) return;

    final color = await extractBrandColorFromImageBytes(bytes);
    if (!mounted || color == null) return;

    setState(() => _logoSuggestedColor = color);
  }

  Future<void> _applyLogoBrandColor({bool showFeedback = false}) async {
    setState(() => _isExtractingColor = true);
    try {
      final bytes = await _currentLogoBytes();
      if (bytes == null) return;

      final color = await extractBrandColorFromImageBytes(bytes);
      if (color == null || !mounted) return;

      setState(() {
        _logoSuggestedColor = color;
        _brandColorController.text = colorToHex(color);
      });

      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Marka rengi logodan alındı: ${colorToHex(color)}'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExtractingColor = false);
    }
  }

  Future<void> _openColorPicker() async {
    final current = parseHexColor(_brandColorController.text);
    final picked = await BrandColorPickerSheet.show(
      context,
      initialColor: current,
      logoSuggestedColor: _logoSuggestedColor,
    );
    if (picked == null || !mounted) return;
    setState(() => _brandColorController.text = colorToHex(picked));
  }

  Future<void> _pickLocation() async {
    final result = await EventLocationPickerSheet.show(
      context,
      initialLat: _locationLat,
      initialLng: _locationLng,
      initialName: _locationNameController.text.trim().isEmpty
          ? null
          : _locationNameController.text.trim(),
    );
    if (result == null || !mounted) return;

    final address =
        await NominatimService().reverseGeocode(result.lat, result.lng);

    setState(() {
      _locationLat = result.lat;
      _locationLng = result.lng;
      _locationAddressController.text =
          address ?? result.name ?? _locationAddressController.text;
      if (_locationNameController.text.trim().isEmpty &&
          result.name != null &&
          result.name!.isNotEmpty) {
        _locationNameController.text = result.name!;
      }
    });
  }

  void _clearLocation() {
    setState(() {
      _locationLat = null;
      _locationLng = null;
      _locationAddressController.clear();
    });
  }

  String _slugify(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  Future<void> _pickLogo() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 90,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      setState(() => _localLogoBytes = bytes);
      await _applyLogoBrandColor();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Logo seçilemedi: $e')),
        );
      }
    }
  }

  Future<void> _pickDate({
    required bool isStart,
  }) async {
    final initial = isStart
        ? (_startsAt ?? DateTime.now())
        : (_endsAt ?? DateTime.now().add(const Duration(days: 30)));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;

    setState(() {
      if (isStart) {
        _startsAt = DateTime(picked.year, picked.month, picked.day);
      } else {
        _endsAt = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
        _hasEndsAt = true;
      }
    });
  }

  bool get _needsUsageLimitCount =>
      _usageLimitType == 'max_total' || _usageLimitType == 'max_per_day';

  Future<void> _save({required String? existingId}) async {
    if (!_formKey.currentState!.validate()) return;

    final slug = _slugController.text.trim().isEmpty
        ? _slugify(_partnerNameController.text.trim())
        : _slugify(_slugController.text.trim());

    if (slug.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Geçerli bir slug girin')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final repo = ref.read(partnerCampaignRepositoryProvider);
      var logoUrl = _existingLogoUrl;

      if (_localLogoBytes != null) {
        logoUrl = await repo.uploadLogo(
          slug: slug,
          bytes: _localLogoBytes!,
        );
      }

      final discountPercent = int.parse(_discountPercentController.text.trim());
      final sortOrder = int.tryParse(_sortOrderController.text.trim()) ?? 0;
      final usageLimitCount = _needsUsageLimitCount
          ? int.tryParse(_usageLimitCountController.text.trim())
          : null;

      if (existingId != null) {
        await repo.updateCampaign(
          id: existingId,
          slug: slug,
          partnerName: _partnerNameController.text.trim(),
          tagline: _taglineController.text,
          logoUrl: logoUrl,
          brandColor: _brandColorController.text.trim(),
          discountPercent: discountPercent,
          discountLabel: _discountLabelController.text.trim(),
          terms: _termsController.text,
          redemptionHint: _redemptionHintController.text.trim(),
          locationName: _locationNameController.text,
          locationAddress: _locationAddressController.text,
          locationLat: _locationLat,
          locationLng: _locationLng,
          startsAt: _startsAt,
          endsAt: _hasEndsAt ? _endsAt : null,
          clearEndsAt: !_hasEndsAt,
          isActive: _isActive,
          sortOrder: sortOrder,
          qrRedemptionEnabled: _qrRedemptionEnabled,
          usageLimitType: _usageLimitType,
          usageLimitCount: usageLimitCount,
          successMessage: _successMessageController.text,
        );
      } else {
        await repo.createCampaign(
          slug: slug,
          partnerName: _partnerNameController.text.trim(),
          tagline: _taglineController.text,
          logoUrl: logoUrl,
          brandColor: _brandColorController.text.trim(),
          discountPercent: discountPercent,
          discountLabel: _discountLabelController.text.trim(),
          terms: _termsController.text,
          redemptionHint: _redemptionHintController.text.trim(),
          locationName: _locationNameController.text,
          locationAddress: _locationAddressController.text,
          locationLat: _locationLat,
          locationLng: _locationLng,
          startsAt: _startsAt,
          endsAt: _hasEndsAt ? _endsAt : null,
          isActive: _isActive,
          sortOrder: sortOrder,
          qrRedemptionEnabled: _qrRedemptionEnabled,
          usageLimitType: _usageLimitType,
          usageLimitCount: usageLimitCount,
          successMessage: _successMessageController.text,
        );
      }

      ref.invalidate(allPartnerCampaignsProvider);
      ref.invalidate(activePartnerCampaignsProvider);
      if (existingId != null) {
        ref.invalidate(partnerCampaignByIdProvider(existingId));
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              existingId != null ? 'Kampanya güncellendi' : 'Kampanya eklendi',
            ),
          ),
        );
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kaydedilemedi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isAdminOrCoachProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor =
        isDark ? AppColors.backgroundDark : AppColors.backgroundLight;

    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.isEditing ? 'Kampanyayı Düzenle' : 'Yeni Kampanya'),
        ),
        body: Center(
          child: Text(
            'Bu sayfaya erişim yetkiniz yok.',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.neutral500,
            ),
          ),
        ),
      );
    }

    if (widget.isEditing) {
      final campaignAsync =
          ref.watch(partnerCampaignByIdProvider(widget.campaignId!));

      return campaignAsync.when(
        loading: () => Scaffold(
          backgroundColor: backgroundColor,
          appBar: AppBar(title: const Text('Kampanyayı Düzenle')),
          body: const LoadingWidget(),
        ),
        error: (e, _) => Scaffold(
          appBar: AppBar(title: const Text('Kampanyayı Düzenle')),
          body: Center(child: Text('Yüklenemedi: $e')),
        ),
        data: (campaign) {
          if (campaign == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('Kampanyayı Düzenle')),
              body: const Center(child: Text('Kampanya bulunamadı')),
            );
          }

          _initFromCampaign(campaign);
          return _buildScaffold(
            backgroundColor: backgroundColor,
            existingId: campaign.id,
          );
        },
      );
    }

    ref.listen(allPartnerCampaignsProvider, (previous, next) {
      next.whenData(_scheduleDefaultSortOrder);
    });
    ref.watch(allPartnerCampaignsProvider).whenData(_scheduleDefaultSortOrder);

    return _buildScaffold(
      backgroundColor: backgroundColor,
      existingId: null,
    );
  }

  Widget _buildScaffold({
    required Color backgroundColor,
    required String? existingId,
  }) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Kampanyayı Düzenle' : 'Yeni Kampanya'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _SaveIconButton(
              isSaving: _isSaving,
              onPressed: () => _save(existingId: existingId),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Center(
              child: GestureDetector(
                onTap: _pickLogo,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: AppColors.neutral200,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.neutral300),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _localLogoBytes != null
                      ? Image.memory(_localLogoBytes!, fit: BoxFit.contain)
                      : _existingLogoUrl != null
                          ? CachedNetworkImage(
                              key: ValueKey(_existingLogoUrl),
                              imageUrl: _existingLogoUrl!,
                              fit: BoxFit.contain,
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.add_photo_alternate_outlined,
                                  color: AppColors.neutral500,
                                  size: 32,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Logo ekle',
                                  style: AppTypography.labelSmall.copyWith(
                                    color: AppColors.neutral500,
                                  ),
                                ),
                              ],
                            ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            AppTextField(
              controller: _partnerNameController,
              label: 'Partner adı',
              hint: 'btw.',
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Zorunlu' : null,
              onChanged: (v) {
                if (!widget.isEditing && _slugController.text.isEmpty) {
                  _slugController.text = _slugify(v);
                }
              },
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: _slugController,
              label: 'Slug (URL)',
              hint: 'btw-coffee',
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: _taglineController,
              label: 'Slogan',
              hint: 'COFFEE & CHILL',
            ),
            const SizedBox(height: 12),
            _BrandColorField(
              hex: _brandColorController.text,
              isLoading: _isExtractingColor,
              onTap: _openColorPicker,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    controller: _discountPercentController,
                    label: 'İndirim %',
                    hint: '10',
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      if (n == null || n <= 0 || n > 100) {
                        return '1-100 arası';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppTextField(
                    controller: _sortOrderController,
                    label: 'Sıra',
                    hint: 'Otomatik',
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _sortOrderUserEdited = true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: _discountLabelController,
              label: 'İndirim açıklaması',
              hint: 'Sandviçlerde %10 indirim',
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Zorunlu' : null,
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: _redemptionHintController,
              label: 'Kullanım talimatı',
              hint: 'Bu ekranı kasada gösterin',
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: _termsController,
              label: 'Koşullar',
              hint: 'Sadece sandviçlerde geçerlidir',
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: _locationNameController,
              label: 'Konum adı (opsiyonel)',
              hint: 'btw. Coffee',
            ),
            const SizedBox(height: 12),
            _LocationPickerField(
              hasLocation: _locationLat != null && _locationLng != null,
              address: _locationAddressController.text,
              onPick: _pickLocation,
              onClear: _clearLocation,
            ),
            const SizedBox(height: 12),
            _DateRangeFields(
              startsAt: _startsAt,
              endsAt: _endsAt,
              hasEndsAt: _hasEndsAt,
              onPickStart: () => _pickDate(isStart: true),
              onPickEnd: () => _pickDate(isStart: false),
              onToggleEnd: (value) => setState(() {
                _hasEndsAt = value;
                if (!value) _endsAt = null;
              }),
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('QR doğrulama aktif'),
              subtitle: const Text(
                'Personel telefon kamerası ile QR okutarak doğrular',
              ),
              value: _qrRedemptionEnabled,
              onChanged: (v) => setState(() => _qrRedemptionEnabled = v),
            ),
            if (_qrRedemptionEnabled) ...[
              const SizedBox(height: 8),
              _UsageLimitDropdown(
                value: _usageLimitType,
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _usageLimitType = v);
                },
              ),
              if (_needsUsageLimitCount) ...[
                const SizedBox(height: 12),
                AppTextField(
                  controller: _usageLimitCountController,
                  label: 'Limit sayısı',
                  hint: '1',
                  keyboardType: TextInputType.number,
                ),
              ],
              const SizedBox(height: 12),
              AppTextField(
                controller: _successMessageController,
                label: 'Başarı mesajı (opsiyonel)',
                hint: 'İndirim uygulandı. Afiyet olsun!',
                maxLines: 2,
              ),
            ],
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Aktif'),
              subtitle: const Text('Kapalıysa uygulamada görünmez'),
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
            ),
          ],
        ),
      ),
    );
  }
}

class _UsageLimitDropdown extends StatelessWidget {
  const _UsageLimitDropdown({
    required this.value,
    required this.onChanged,
  });

  static const _options = {
    'unlimited': 'Sınırsız',
    'once_lifetime': 'Tek sefer (ömür boyu)',
    'once_per_day': 'Günde 1 kez',
    'once_per_week': 'Haftada 1 kez',
    'max_total': 'Toplam N kez',
    'max_per_day': 'Günde N kez',
  };

  final String value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Kullanım limiti',
          style: AppTypography.labelMedium.copyWith(
            color: AppColors.neutral600,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: value,
          decoration: InputDecoration(
            filled: true,
            fillColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          items: _options.entries
              .map(
                (e) => DropdownMenuItem(
                  value: e.key,
                  child: Text(e.value),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _DateRangeFields extends StatelessWidget {
  const _DateRangeFields({
    required this.startsAt,
    required this.endsAt,
    required this.hasEndsAt,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onToggleEnd,
  });

  final DateTime? startsAt;
  final DateTime? endsAt;
  final bool hasEndsAt;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final ValueChanged<bool> onToggleEnd;

  String _format(DateTime? date) {
    if (date == null) return 'Seçilmedi';
    return DateFormat('d MMM yyyy', 'tr_TR').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DateTile(
          label: 'Başlangıç tarihi',
          value: _format(startsAt),
          onTap: onPickStart,
        ),
        const SizedBox(height: 8),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Bitiş tarihi var'),
          value: hasEndsAt,
          onChanged: onToggleEnd,
        ),
        if (hasEndsAt)
          _DateTile(
            label: 'Bitiş tarihi',
            value: _format(endsAt),
            onTap: onPickEnd,
          ),
      ],
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.labelMedium.copyWith(
            color: AppColors.neutral600,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Material(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark
                      ? AppColors.surfaceVariantDark
                      : AppColors.neutral300,
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_outlined, size: 20),
                  const SizedBox(width: 12),
                  Expanded(child: Text(value)),
                  const Icon(Icons.chevron_right, color: AppColors.neutral400),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LocationPickerField extends StatelessWidget {
  const _LocationPickerField({
    required this.hasLocation,
    required this.address,
    required this.onPick,
    required this.onClear,
  });

  final bool hasLocation;
  final String address;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Adres (opsiyonel)',
          style: AppTypography.labelMedium.copyWith(
            color: AppColors.neutral600,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Material(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onPick,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: hasLocation
                      ? AppColors.success
                      : (isDark
                          ? AppColors.surfaceVariantDark
                          : AppColors.neutral300),
                ),
                color: hasLocation
                    ? AppColors.success.withValues(alpha: 0.06)
                    : null,
              ),
              child: Row(
                children: [
                  Icon(
                    hasLocation
                        ? Icons.location_on_rounded
                        : Icons.add_location_alt_outlined,
                    color: hasLocation
                        ? AppColors.success
                        : AppColors.neutral500,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      hasLocation && address.isNotEmpty
                          ? address
                          : 'Haritadan adres seçin',
                      style: AppTypography.bodyMedium.copyWith(
                        color: hasLocation
                            ? AppColors.neutral800
                            : AppColors.neutral500,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (hasLocation)
                    IconButton(
                      tooltip: 'Adresi kaldır',
                      icon: const Icon(Icons.clear, size: 20),
                      color: AppColors.neutral500,
                      onPressed: onClear,
                    )
                  else
                    Icon(
                      Icons.chevron_right,
                      color: AppColors.neutral400,
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BrandColorField extends StatelessWidget {
  const _BrandColorField({
    required this.hex,
    required this.onTap,
    this.isLoading = false,
  });

  final String hex;
  final VoidCallback onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final color = parseHexColor(hex);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Marka rengi',
          style: AppTypography.labelMedium.copyWith(
            color: AppColors.neutral600,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Material(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: isLoading ? null : onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark
                      ? AppColors.surfaceVariantDark
                      : AppColors.neutral300,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.neutral300),
                    ),
                    child: isLoading
                        ? const Padding(
                            padding: EdgeInsets.all(8),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hex.toUpperCase(),
                          style: AppTypography.titleSmall.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Logodan otomatik dolar · Paleti açmak için dokun',
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.neutral500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.palette_outlined,
                    color: AppColors.neutral500,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SaveIconButton extends StatelessWidget {
  const _SaveIconButton({
    required this.isSaving,
    required this.onPressed,
  });

  final bool isSaving;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Kaydet',
      child: Material(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: isSaving ? null : onPressed,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 40,
            height: 40,
            child: isSaving
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                : const Icon(
                    Icons.check_rounded,
                    color: AppColors.primary,
                    size: 22,
                  ),
          ),
        ),
      ),
    );
  }
}
