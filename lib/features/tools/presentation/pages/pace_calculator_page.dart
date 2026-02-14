import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/vdot_calculator.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../../events/domain/entities/event_entity.dart' show TrainingTypeEntity;
import '../../../events/presentation/providers/event_provider.dart';

/// VDOT Calculator Page
class PaceCalculatorPage extends ConsumerStatefulWidget {
  const PaceCalculatorPage({super.key});

  @override
  ConsumerState<PaceCalculatorPage> createState() => _PaceCalculatorPageState();
}

class _PaceCalculatorPageState extends ConsumerState<PaceCalculatorPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // VDOT Calculator
  String _selectedDistance = '5K';
  final _hoursController = TextEditingController();
  final _minutesController = TextEditingController();
  final _secondsController = TextEditingController();

  // Cooper Test
  final _cooperDistanceController = TextEditingController();

  double? _calculatedVdot;
  bool _isSaving = false;
  bool _showCalculator = false; // Hesaplama modunu göster/gizle

  // Lane Calculator
  int _selectedLane = 1;
  final _lapsController = TextEditingController(text: '1');
  String _selectedTrainingType = 'Interval'; // Pist antrenmanı için seçili tür
  
  // Pist antrenmanı türleri ve VO2max yüzdeleri
  static const Map<String, double> _trackTrainingTypes = {
    'Easy Run': 0.70,
    'Marathon Pace': 0.80,
    'Threshold': 0.88,
    'Interval': 0.98,
    'Repetition': 1.05,
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _hoursController.dispose();
    _minutesController.dispose();
    _secondsController.dispose();
    _cooperDistanceController.dispose();
    _lapsController.dispose();
    super.dispose();
  }

  void _calculateVdotFromRace() {
    final distance = VdotCalculator.standardDistances[_selectedDistance];
    if (distance == null) return;

    final hours = int.tryParse(_hoursController.text) ?? 0;
    final minutes = int.tryParse(_minutesController.text) ?? 0;
    final seconds = int.tryParse(_secondsController.text) ?? 0;

    final totalSeconds = hours * 3600 + minutes * 60 + seconds;
    if (totalSeconds <= 0) return;

    final vdot = VdotCalculator.calculateFromRace(distance, totalSeconds);
    
    setState(() {
      _calculatedVdot = vdot;
    });
  }

  void _calculateVdotFromCooper() {
    final distance = double.tryParse(_cooperDistanceController.text);
    if (distance == null || distance <= 0) return;

    final vdot = VdotCalculator.calculateFromCooperTest(distance);
    
    setState(() {
      _calculatedVdot = vdot;
    });
  }

  Future<void> _saveVdot() async {
    if (_calculatedVdot == null) return;

    setState(() => _isSaving = true);

    final success = await ref.read(vdotUpdateProvider.notifier).updateVdot(_calculatedVdot!);

    setState(() => _isSaving = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success 
            ? 'VDOT değerin kaydedildi!' 
            : 'VDOT kaydedilemedi'),
          backgroundColor: success ? AppColors.success : AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentVdot = ref.watch(userVdotProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.goNamed(RouteNames.home);
            }
          },
        ),
        title: const Text('VDOT Hesaplayıcı'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'VDOT Hesapla'),
            Tab(text: 'Pist Kulvarı'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildVdotCalculator(currentVdot),
          _buildLaneCalculator(),
        ],
      ),
    );
  }

  Widget _buildVdotCalculator(double? currentVdot) {
    final hasVdot = currentVdot != null && currentVdot > 0;
    final showPaces = hasVdot && !_showCalculator;
    
    final displayVdot = showPaces ? currentVdot : _calculatedVdot;
    final trainingTypesAsync = ref.watch(trainingTypesProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mevcut VDOT kartı (her zaman göster eğer varsa)
          if (hasVdot) ...[
            AppCard(
              gradient: AppColors.primaryGradient,
              child: Row(
                children: [
                  const Icon(Icons.speed, color: Colors.white, size: 32),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mevcut VDOT',
                          style: AppTypography.labelMedium.copyWith(
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                        Text(
                          currentVdot.toStringAsFixed(1),
                          style: AppTypography.headlineMedium.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!_showCalculator)
                    IconButton(
                      onPressed: () => setState(() => _showCalculator = true),
                      icon: const Icon(Icons.edit, color: Colors.white),
                      tooltip: 'Yeni VDOT Hesapla',
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          // VDOT yoksa veya hesaplama modu açıksa
          if (!hasVdot || _showCalculator) ...[
            // Hesaplama modundayken geri butonu
            if (_showCalculator && hasVdot) ...[
              OutlinedButton.icon(
                onPressed: () => setState(() {
                  _showCalculator = false;
                  _calculatedVdot = null;
                }),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Pace\'lerime Dön'),
              ),
              const SizedBox(height: 16),
            ],
            
            // Açıklama
            Text(
              'VDOT Nedir?',
              style: AppTypography.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'VDOT, Jack Daniels tarafından geliştirilen ve koşu performansını ölçen bir değerdir. '
              'Yarış sonucunuza göre hesaplanır ve farklı antrenman türleri için ideal pace\'lerinizi belirler.',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.neutral600,
              ),
            ),
            const SizedBox(height: 24),

            // Yarış sonucundan hesapla
            _buildRaceCalculator(),
            const SizedBox(height: 24),

            // Cooper testinden hesapla
            _buildCooperCalculator(),
            const SizedBox(height: 24),

            // Yeni hesaplanan sonuçlar
            if (_calculatedVdot != null) ...[
              _buildVdotResult(),
              const SizedBox(height: 24),
            ],
          ],

          // Pace'ler ve tahmini süreler (mevcut veya yeni hesaplanan)
          if (displayVdot != null && displayVdot > 0) ...[
            trainingTypesAsync.when(
              data: (trainingTypes) => _buildTrainingPacesWithData(displayVdot, trainingTypes),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 24),
            _buildPredictedTimesWithVdot(displayVdot),
          ],

          // VDOT yoksa "Yeni VDOT Hesapla" butonu
          if (!hasVdot && _calculatedVdot == null) ...[
            const SizedBox(height: 24),
            Center(
              child: Text(
                'Yukarıdan yarış sonucunu veya Cooper test mesafesini girerek VDOT\'unu hesapla!',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.neutral500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildTrainingPacesWithData(double vdot, List<TrainingTypeEntity> trainingTypes) {
    // Eşik pace göster
    final thresholdPace = VdotCalculator.getThresholdPace(vdot);

    // Renk paleti: training type color'dan parse et
    Color parseColor(String hex) {
      try {
        return Color(int.parse('FF${hex.replaceFirst('#', '')}', radix: 16));
      } catch (_) {
        return AppColors.primary;
      }
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.directions_run, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'Antrenman Pace\'lerin',
                style: AppTypography.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Eşik Tempon: ${VdotCalculator.formatPace(thresholdPace)} /km',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.neutral600,
            ),
          ),
          const SizedBox(height: 16),
          ...trainingTypes.where((t) => t.thresholdOffsetMinSeconds != null && t.thresholdOffsetMaxSeconds != null).map((type) {
            final paceRange = VdotCalculator.formatPaceRange(
              vdot,
              type.thresholdOffsetMinSeconds,
              type.thresholdOffsetMaxSeconds,
            );
            return _buildPaceRow(
              type.displayName,
              paceRange ?? '--:--',
              parseColor(type.color),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildPredictedTimesWithVdot(double vdot) {
    final predictions = {
      '5K': VdotCalculator.predictRaceTime(vdot, 5000),
      '10K': VdotCalculator.predictRaceTime(vdot, 10000),
      'Yarı Maraton': VdotCalculator.predictRaceTime(vdot, 21097.5),
      'Maraton': VdotCalculator.predictRaceTime(vdot, 42195),
    };

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule, color: AppColors.tertiary),
              const SizedBox(width: 8),
              Text(
                'Tahmini Yarış Sürelerin',
                style: AppTypography.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...predictions.entries.map((entry) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(entry.key, style: AppTypography.bodyMedium),
                Text(
                  VdotCalculator.formatDuration(entry.value),
                  style: AppTypography.titleSmall.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildRaceCalculator() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.emoji_events, color: AppColors.secondary),
              const SizedBox(width: 8),
              Text(
                'Yarış Sonucundan Hesapla',
                style: AppTypography.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Mesafe seçimi
          Text('Yarış Mesafesi', style: AppTypography.labelMedium),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.neutral300),
              borderRadius: BorderRadius.circular(12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedDistance,
                isExpanded: true,
                icon: const Icon(Icons.keyboard_arrow_down),
                items: VdotCalculator.standardDistances.keys.map((distance) {
                  return DropdownMenuItem<String>(
                    value: distance,
                    child: Text(distance, style: AppTypography.bodyLarge),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedDistance = value);
                    _calculateVdotFromRace();
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Süre girişi
          Text('Bitiş Süreniz', style: AppTypography.labelMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  controller: _hoursController,
                  hint: 'Saat',
                  keyboardType: TextInputType.number,
                  onChanged: (_) => _calculateVdotFromRace(),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(':'),
              ),
              Expanded(
                child: AppTextField(
                  controller: _minutesController,
                  hint: 'Dakika',
                  keyboardType: TextInputType.number,
                  onChanged: (_) => _calculateVdotFromRace(),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(':'),
              ),
              Expanded(
                child: AppTextField(
                  controller: _secondsController,
                  hint: 'Saniye',
                  keyboardType: TextInputType.number,
                  onChanged: (_) => _calculateVdotFromRace(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCooperCalculator() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.timer, color: AppColors.tertiary),
              const SizedBox(width: 8),
              Text(
                'Cooper Testinden Hesapla',
                style: AppTypography.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '12 dakikada koştuğunuz mesafeyi girin',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.neutral500,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  controller: _cooperDistanceController,
                  hint: 'Mesafe (metre)',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => _calculateVdotFromCooper(),
                ),
              ),
              const SizedBox(width: 8),
              const Text('metre'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVdotResult() {
    return AppCard(
      backgroundColor: AppColors.successContainer,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.speed, color: AppColors.success, size: 32),
              const SizedBox(width: 12),
              Text(
                'VDOT: ${_calculatedVdot!.toStringAsFixed(1)}',
                style: AppTypography.headlineMedium.copyWith(
                  color: AppColors.success,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AppButton(
            text: 'Profime Kaydet',
            icon: Icons.save,
            isLoading: _isSaving,
            onPressed: _saveVdot,
            isFullWidth: true,
          ),
        ],
      ),
    );
  }

  Widget _buildPaceRow(String label, String pace, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 32,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: AppTypography.bodyMedium,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$pace /km',
              style: AppTypography.titleSmall.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLaneCalculator() {
    final userVdot = ref.watch(userVdotProvider);
    
    // Lane distances (standard 400m track)
    final laneDistances = [
      400.0, 407.67, 415.33, 423.0, 430.66, 438.33, 446.0, 453.66,
    ];

    final laps = int.tryParse(_lapsController.text) ?? 1;
    final selectedDistance = laneDistances[_selectedLane - 1] * laps;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pist kulvarına göre toplam mesafeyi ve antrenman süresini hesapla',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.neutral500,
            ),
          ),
          const SizedBox(height: 24),

          // Antrenman Türü Seçimi
          Text('Antrenman Türü', style: AppTypography.labelMedium),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.neutral300),
              borderRadius: BorderRadius.circular(12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedTrainingType,
                isExpanded: true,
                icon: const Icon(Icons.keyboard_arrow_down),
                items: _trackTrainingTypes.keys.map((type) {
                  return DropdownMenuItem<String>(
                    value: type,
                    child: Text(type, style: AppTypography.bodyLarge),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedTrainingType = value);
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 24),

          AppTextField(
            controller: _lapsController,
            label: 'Tur Sayısı',
            hint: '1',
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 24),

          Text('Kulvar Seçin', style: AppTypography.titleSmall),
          const SizedBox(height: 12),
          _buildLaneSelector(),
          const SizedBox(height: 24),
          
          // Kullanıcının VDOT'una göre koşu süresi hesaplama
          if (userVdot != null && userVdot > 0) ...[
            _buildTrackTimingCard(userVdot, laneDistances, laps, selectedDistance),
            const SizedBox(height: 24),
          ] else ...[
            // VDOT yoksa sadece mesafe bilgisi göster
            AppCard(
              gradient: AppColors.primaryGradient,
              child: Column(
                children: [
                  Text(
                    '$laps Tur • Kulvar $_selectedLane',
                    style: AppTypography.titleSmall.copyWith(
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${selectedDistance.toStringAsFixed(0)} m',
                    style: AppTypography.displaySmall.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '(${(selectedDistance / 1000).toStringAsFixed(2)} km)',
                    style: AppTypography.bodyMedium.copyWith(
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AppCard(
              backgroundColor: AppColors.warningContainer,
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: AppColors.warning),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Koşu süresi hesaplaması için önce VDOT değerini hesaplayın.',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          Text('Kulvar Mesafeleri (1 Tur)', style: AppTypography.titleSmall),
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              children: [
                for (int i = 0; i < 8; i++) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Kulvar ${i + 1}',
                        style: AppTypography.bodyMedium.copyWith(
                          fontWeight: _selectedLane == i + 1
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: _selectedLane == i + 1
                              ? AppColors.primary
                              : null,
                        ),
                      ),
                      Text(
                        '${laneDistances[i].toStringAsFixed(2)} m',
                        style: AppTypography.bodyMedium.copyWith(
                          fontWeight: _selectedLane == i + 1
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: _selectedLane == i + 1
                              ? AppColors.primary
                              : AppColors.neutral500,
                        ),
                      ),
                    ],
                  ),
                  if (i < 7) const Divider(height: 16),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLaneSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(
        8,
        (index) {
          final lane = index + 1;
          final isSelected = _selectedLane == lane;

          return GestureDetector(
            onTap: () => setState(() => _selectedLane = lane),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : AppColors.neutral200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  '$lane',
                  style: AppTypography.titleSmall.copyWith(
                    color: isSelected ? Colors.white : AppColors.neutral600,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTrackTimingCard(double vdot, List<double> laneDistances, int laps, double selectedDistance) {
    final intensityPercent = _trackTrainingTypes[_selectedTrainingType] ?? 0.98;
    
    // Pace hesapla (saniye/km)
    final paceSecondsPerKm = _calculatePaceFromVdotIntensity(vdot, intensityPercent);
    final paceFormatted = VdotCalculator.formatPace(paceSecondsPerKm.round());
    
    // Her kulvar için süre hesapla
    List<int> laneTimes = [];
    for (int i = 0; i < 8; i++) {
      final distanceKm = (laneDistances[i] * laps) / 1000;
      final timeSeconds = (paceSecondsPerKm * distanceKm).round();
      laneTimes.add(timeSeconds);
    }
    
    final selectedLaneTime = laneTimes[_selectedLane - 1];
    
    return AppCard(
      backgroundColor: AppColors.successContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.timer, color: AppColors.success, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$_selectedTrainingType Antrenmanı',
                      style: AppTypography.titleSmall.copyWith(
                        color: AppColors.success,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Pace: $paceFormatted /km',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.neutral600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Seçili kulvar için süre ve mesafe
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${selectedDistance.toStringAsFixed(0)} m',
                      style: AppTypography.headlineSmall.copyWith(
                        color: AppColors.success,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      ' (${(selectedDistance / 1000).toStringAsFixed(2)} km)',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.neutral600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Kulvar $_selectedLane • $laps Tur',
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.neutral500,
                  ),
                ),
                const Divider(height: 24),
                Text(
                  _formatTime(selectedLaneTime),
                  style: AppTypography.displaySmall.copyWith(
                    color: AppColors.success,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'koşmalısın',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.neutral500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          
          // Tüm kulvarlar için süreler
          Text(
            'Tüm Kulvarlar İçin Süreler',
            style: AppTypography.labelMedium.copyWith(
              color: AppColors.neutral600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(8, (index) {
              final isSelected = _selectedLane == index + 1;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected 
                      ? AppColors.success.withValues(alpha: 0.2)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected 
                        ? AppColors.success 
                        : AppColors.neutral200,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      'K${index + 1}',
                      style: AppTypography.labelSmall.copyWith(
                        color: isSelected ? AppColors.success : AppColors.neutral500,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _formatTime(laneTimes[index]),
                      style: AppTypography.bodySmall.copyWith(
                        color: isSelected ? AppColors.success : AppColors.neutral700,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  double _calculatePaceFromVdotIntensity(double vdot, double intensityPercent) {
    // VO2 from VDOT
    final vo2 = vdot * intensityPercent;

    // Velocity from VO2 (ters formül)
    // VO2 = -4.60 + 0.182258 * v + 0.000104 * v^2
    final a = 0.000104;
    final b = 0.182258;
    final c = -4.60 - vo2;

    final discriminant = b * b - 4 * a * c;
    if (discriminant < 0) return 0;

    final velocity = (-b + sqrt(discriminant)) / (2 * a); // m/min

    if (velocity <= 0) return 0;

    // Pace = 1000 / velocity * 60 (saniye/km)
    return (1000 / velocity) * 60;
  }

  String _formatTime(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
