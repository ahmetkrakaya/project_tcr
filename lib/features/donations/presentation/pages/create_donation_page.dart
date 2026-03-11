import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../providers/donation_provider.dart';
import '../providers/foundation_provider.dart';

class CreateDonationPage extends ConsumerStatefulWidget {
  const CreateDonationPage({super.key});

  @override
  ConsumerState<CreateDonationPage> createState() => _CreateDonationPageState();
}

class _CreateDonationPageState extends ConsumerState<CreateDonationPage> {
  final _formKey = GlobalKey<FormState>();
  final _raceNameController = TextEditingController();
  final _amountController = TextEditingController();

  bool _isFromEvent = true;
  String? _selectedEventId;
  String? _selectedFoundationId;
  DateTime? _selectedRaceDate;

  @override
  void dispose() {
    _raceNameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final creationState = ref.watch(donationCreationProvider);
    final isLoading = creationState is AsyncLoading;
    final eventsAsync = ref.watch(userParticipatedRaceEventsProvider);
    final foundationsAsync = ref.watch(foundationsProvider);
    final dateFormat = DateFormat('d MMMM yyyy, EEEE', 'tr_TR');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bağış Ekle'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Yarış seçim türü
            Text(
              'Yarış Kaynağı',
              style: AppTypography.labelLarge.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  label: Text('Etkinlikten Seç'),
                  icon: Icon(Icons.event),
                ),
                ButtonSegment(
                  value: false,
                  label: Text('Manuel Giriş'),
                  icon: Icon(Icons.edit),
                ),
              ],
              selected: {_isFromEvent},
              onSelectionChanged: (selected) {
                setState(() {
                  _isFromEvent = selected.first;
                  _selectedEventId = null;
                  _raceNameController.clear();
                  _selectedRaceDate = null;
                });
              },
            ),
            const SizedBox(height: 20),

            // Etkinlikten seçim
            if (_isFromEvent) ...[
              Text(
                'Yarış Etkinliği',
                style: AppTypography.labelLarge.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              eventsAsync.when(
                data: (events) {
                  if (events.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.warning.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              color: AppColors.warning, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Katıldığınız bir yarış etkinliği bulunamadı. Manuel giriş yapabilirsiniz.',
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.warning,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return DropdownButtonFormField<String>(
                    value: _selectedEventId,
                    decoration: InputDecoration(
                      hintText: 'Yarış seçin',
                      prefixIcon: const Icon(Icons.emoji_events_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: events.map((event) {
                      final eventDate = DateTime.parse(
                          event['start_time'] as String);
                      final formatted = DateFormat('d MMM yyyy', 'tr_TR')
                          .format(eventDate);
                      return DropdownMenuItem(
                        value: event['id'] as String,
                        child: Text(
                          '${event['title']} ($formatted)',
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedEventId = value;
                      });
                    },
                    validator: (value) {
                      if (_isFromEvent && (value == null || value.isEmpty)) {
                        return 'Lütfen bir yarış seçin';
                      }
                      return null;
                    },
                  );
                },
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (error, _) => Text(
                  'Etkinlikler yüklenemedi: $error',
                  style: TextStyle(color: AppColors.error),
                ),
              ),
            ],

            // Manuel giriş
            if (!_isFromEvent) ...[
              AppTextField(
                controller: _raceNameController,
                label: 'Yarış Adı',
                hint: 'ör: İstanbul Maratonu',
                prefixIcon: Icons.directions_run,
                validator: (value) {
                  if (!_isFromEvent &&
                      (value == null || value.trim().isEmpty)) {
                    return 'Yarış adı gerekli';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: _pickDate,
                child: AbsorbPointer(
                  child: AppTextField(
                    controller: TextEditingController(
                      text: _selectedRaceDate != null
                          ? dateFormat.format(_selectedRaceDate!)
                          : '',
                    ),
                    label: 'Yarış Tarihi',
                    hint: 'Tarih seçin',
                    prefixIcon: Icons.calendar_today,
                    validator: (value) {
                      if (!_isFromEvent && _selectedRaceDate == null) {
                        return 'Yarış tarihi seçilmeli';
                      }
                      return null;
                    },
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),

            // Vakıf seçimi
            Text(
              'Vakıf / Kuruluş',
              style: AppTypography.labelLarge.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            foundationsAsync.when(
              data: (foundations) {
                if (foundations.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.warning.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            color: AppColors.warning, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Henüz vakıf eklenmemiş. Admin bir vakıf ekleyene kadar bağış kaydedemezsiniz.',
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.warning,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return DropdownButtonFormField<String>(
                  value: _selectedFoundationId,
                  decoration: InputDecoration(
                    hintText: 'Vakıf seçin',
                    prefixIcon: const Icon(Icons.favorite_outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: foundations.map((f) {
                    return DropdownMenuItem(
                      value: f.id,
                      child: Text(f.name, overflow: TextOverflow.ellipsis),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() => _selectedFoundationId = value);
                  },
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Lütfen bir vakıf seçin';
                    }
                    return null;
                  },
                );
              },
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (error, _) => Text(
                'Vakıflar yüklenemedi: $error',
                style: TextStyle(color: AppColors.error),
              ),
            ),
            const SizedBox(height: 16),

            // Tutar
            AppTextField(
              controller: _amountController,
              label: 'Toplanan Bağış Tutarı (₺)',
              hint: 'ör: 5000',
              prefixIcon: Icons.attach_money,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Tutar gerekli';
                }
                final amount = double.tryParse(value.trim());
                if (amount == null || amount < 0) {
                  return 'Geçerli bir tutar girin (0 veya üzeri).';
                }
                return null;
              },
            ),
            const SizedBox(height: 32),

            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: isLoading ? null : _submit,
                child: isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Bağışı Kaydet'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedRaceDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('tr', 'TR'),
    );
    if (picked != null) {
      setState(() {
        _selectedRaceDate = picked;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final amount = double.parse(_amountController.text.trim());

    final foundationId = _selectedFoundationId;
    if (foundationId == null || foundationId.isEmpty) return;

    final bool success;
    if (_isFromEvent) {
      success = await ref.read(donationCreationProvider.notifier).createDonation(
            eventId: _selectedEventId,
            foundationId: foundationId,
            amount: amount,
          );
    } else {
      success = await ref.read(donationCreationProvider.notifier).createDonation(
            raceName: _raceNameController.text.trim(),
            raceDate: _selectedRaceDate,
            foundationId: foundationId,
            amount: amount,
          );
    }

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bağış kaydedildi'),
            backgroundColor: AppColors.success,
          ),
        );
        context.pop();
      } else {
        final errorState = ref.read(donationCreationProvider);
        final message = _userFriendlyError(errorState);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  String _userFriendlyError(AsyncValue<void> state) {
    final error = state.error;
    if (error is PostgrestException) {
      if (error.code == '23505') {
        return 'Bu yarış için zaten bir bağış kaydınız var. Mevcut bağışınızı güncelleyebilirsiniz.';
      }
      if (error.code == '23503') {
        return 'Seçtiğiniz etkinlik bulunamadı. Lütfen tekrar deneyin.';
      }
      if (error.code == '23514') {
        // CHECK constraint ihlali. Normalde insert'te 0 kabul; bu hata geliyorsa DB migration uygulanmamış olabilir.
        return 'Bağış tutarı geçersiz. Eğer 0 giriyorsanız, veritabanı güncellemesi henüz uygulanmamış olabilir.';
      }
      return 'Veritabanı hatası: ${error.message}';
    }
    return error?.toString() ?? 'Bilinmeyen bir hata oluştu';
  }
}
