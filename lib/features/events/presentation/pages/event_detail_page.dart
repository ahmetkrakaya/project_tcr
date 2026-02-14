import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb, TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/vdot_calculator.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/flip_countdown_widget.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../../carpool/presentation/widgets/event_carpool_section.dart';
import '../../../chat/presentation/providers/chat_provider.dart';
import '../../../members_groups/presentation/widgets/user_group_program_viewer.dart';
import '../../../routes/presentation/providers/route_provider.dart';
import '../../domain/entities/event_result_entity.dart';
import '../../domain/entities/event_entity.dart';
import '../../domain/repositories/event_results_repository.dart';
import '../providers/event_provider.dart';
import '../widgets/event_info_blocks_viewer.dart';

/// Event Detail Page
class EventDetailPage extends ConsumerStatefulWidget {
  final String eventId;

  const EventDetailPage({super.key, required this.eventId});

  @override
  ConsumerState<EventDetailPage> createState() => _EventDetailPageState();
}

class _EventDetailPageState extends ConsumerState<EventDetailPage> {
  bool _isBannerUploading = false;
  final String _selectedRankingType = 'overall'; // 'overall', 'female', 'male'

  @override
  Widget build(BuildContext context) {
    final eventAsync = ref.watch(eventByIdProvider(widget.eventId));
    final participantsAsync = ref.watch(eventParticipantsProvider(widget.eventId));
    final resultsAsync = ref.watch(eventResultsProvider(widget.eventId));
    final isAdminOrCoach = ref.watch(isAdminOrCoachProvider);
    final rsvpState = ref.watch(rsvpProvider);

    return eventAsync.when(
      data: (event) => _buildContent(
        context,
        ref,
        event,
        participantsAsync,
        resultsAsync,
        isAdminOrCoach,
        rsvpState,
      ),
      loading: () => const Scaffold(
        body: Center(child: LoadingWidget()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(),
        body: isContentNotFoundError(error)
            ? ContentNotFoundWidget(
                onGoToNotifications: () =>
                    context.goNamed(RouteNames.notifications),
                onBack: () => context.pop(),
              )
            : Center(
                child: ErrorStateWidget(
                  title: 'Etkinlik yüklenemedi',
                  message: error.toString(),
                  onRetry: () =>
                      ref.invalidate(eventByIdProvider(widget.eventId)),
                ),
              ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    EventEntity event,
    AsyncValue<List<EventParticipantEntity>> participantsAsync,
    AsyncValue<List<EventResultEntity>> resultsAsync,
    bool isAdminOrCoach,
    AsyncValue<void> rsvpState,
  ) {
    // Chat verilerini önceden yükle (katılımcılar için)
    if (event.isUserParticipating) {
      prefetchEventChat(ref, widget.eventId);
    }

    // RSVP hata durumunu dinle
    ref.listen<AsyncValue<void>>(rsvpProvider, (previous, next) {
      next.whenOrNull(
        error: (error, _) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Katılım kaydedilemedi: $error'),
              backgroundColor: AppColors.error,
            ),
          );
        },
        data: (_) {
          // Başarılı olduğunda bir şey yapmaya gerek yok, 
          // provider zaten invalidate ediyor
        },
      );
    });

    final screenHeight = MediaQuery.sizeOf(context).height;
    final appBarHeight = (screenHeight * 0.24).clamp(180.0, 260.0);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App Bar with Image/Banner
          SliverAppBar(
            expandedHeight: appBarHeight,
            pinned: true,
            foregroundColor: Colors.white,
            iconTheme: const IconThemeData(color: Colors.white),
            leading: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: _buildBannerBackground(context, event, isAdminOrCoach, ref),
            ),
            actions: [
              Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: Builder(
                  builder: (ctx) {
                    return IconButton(
                      icon: const Icon(Icons.share),
                      splashRadius: 24,
                      onPressed: () async {
                        try {
                          final shareUrl =
                              AppConstants.eventShareUrlShort(event.id);
                          final box =
                              ctx.findRenderObject() as RenderBox?;
                          final shareOrigin = box != null
                              ? Rect.fromPoints(
                                  box.localToGlobal(Offset.zero),
                                  box.localToGlobal(box.size.bottomRight(Offset.zero)),
                                )
                              : const Rect.fromLTWH(0, 0, 1, 1);
                          await Share.share(
                            shareUrl,
                            subject: 'TCR Etkinlik: ${event.title}',
                            sharePositionOrigin: shareOrigin,
                          );
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Paylaşım açılamadı: ${e.toString()}',
                                ),
                                backgroundColor: AppColors.error,
                              ),
                            );
                          }
                        }
                      },
                    );
                  },
                ),
              ),
              if (isAdminOrCoach)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  child: PopupMenuButton<String>(
                  onSelected: (value) async {
                    final router = GoRouter.of(context);
                    switch (value) {
                      case 'edit':
                        if (event.isPartOfRecurringSeries) {
                          final scope = await _showRecurringEditScopeDialog(context);
                          if (scope != null && context.mounted) {
                            router.pushNamed(
                              RouteNames.editEvent,
                              pathParameters: {'eventId': widget.eventId},
                              queryParameters: {'scope': scope},
                            );
                          }
                        } else {
                          context.pushNamed(
                            RouteNames.editEvent,
                            pathParameters: {'eventId': widget.eventId},
                          );
                        }
                        break;
                      case 'save_template':
                        _showSaveAsTemplateDialog(context, ref, event);
                        break;
                      case 'delete':
                        _showDeleteConfirmation(context, ref);
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined),
                          SizedBox(width: 8),
                          Text('Düzenle'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'save_template',
                      child: Row(
                        children: [
                          Icon(Icons.bookmark_add_outlined, color: AppColors.primary),
                          SizedBox(width: 8),
                          Text('Şablon Olarak Kaydet', style: TextStyle(color: AppColors.primary)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, color: AppColors.error),
                          SizedBox(width: 8),
                          Text('Sil', style: TextStyle(color: AppColors.error)),
                        ],
                      ),
                    ),
                  ],
                  ),
                ),
            ],
          ),

          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sol: Yarış altında Başlık — Sağ: Geri sayım
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _getEventTypeColor(event.eventType).withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    event.eventType.displayName,
                                    style: AppTypography.labelMedium.copyWith(
                                      color: _getEventTypeColor(event.eventType),
                                    ),
                                  ),
                                ),
                                if (event.eventType == EventType.training)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _isIndividualParticipation(event)
                                          ? AppColors.primary.withValues(alpha: 0.2)
                                          : AppColors.tertiary.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      _isIndividualParticipation(event) ? 'Bireysel' : 'Ekip',
                                      style: AppTypography.labelMedium.copyWith(
                                        color: _isIndividualParticipation(event)
                                            ? AppColors.primary
                                            : AppColors.tertiary,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              event.title,
                              style: AppTypography.headlineSmall,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (event.eventType == EventType.race &&
                          event.startTime.isAfter(DateTime.now())) ...[
                        const SizedBox(width: 12),
                        FlipCountdownWidget(targetDate: event.startTime),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Tarih · Saat · Konum/Rota tek kompakt satırda
                  _buildCompactDateLocationRow(context, ref, event),
                  const SizedBox(height: 16),

                  // Weather Note
                  if (event.weatherNote != null && event.weatherNote!.isNotEmpty)
                    _buildInfoRow(
                      icon: Icons.wb_sunny_outlined,
                      title: 'Hava Durumu Notu',
                      subtitle: event.weatherNote!,
                    ),
                  if (event.weatherNote != null) const SizedBox(height: 24),

                  // Training Type (Antrenman Türü)
                  if (event.trainingTypeName != null) ...[
                    _buildTrainingTypeCard(context, event, ref),
                    const SizedBox(height: 24),
                  ],

                  // Description
                  if (event.description != null && event.description!.isNotEmpty) ...[
                    Text(
                      'Açıklama',
                      style: AppTypography.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      event.description!,
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.neutral600,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Antrenman ise kullanıcının grup programları; değilse Etkinlik Programı & Bilgiler
                  if (event.eventType == EventType.training)
                    UserGroupProgramViewer(eventId: widget.eventId),

                  // Event Info Blocks (Notion benzeri) - antrenman dışında her zaman kart gösterilir
                  EventInfoBlocksViewer(
                    eventId: widget.eventId,
                    eventTitle: event.title,
                    showEditButton: isAdminOrCoach,
                    showWhenEmpty: event.eventType != EventType.training,
                  ),
                  const SizedBox(height: 8),

                  // Ortak Araba (sadece Ekip / toplu antrenmanda; bireyselde yok; geçmiş etkinliklerde gösterilmez)
                  if (!_isIndividualParticipation(event) && !event.isPast) ...[
                    EventCarpoolSection(eventId: widget.eventId),
                    const SizedBox(height: 24),
                  ],

                  // Chat Section (Sadece katılımcılar için)
                  if (event.isUserParticipating)
                    _buildChatSection(context, widget.eventId, event),
                  if (event.isUserParticipating) const SizedBox(height: 24),

                  // Participants Section (sadece Ekip / toplu antrenmanda)
                  if (!_isIndividualParticipation(event)) ...[
                    _buildSectionHeader(
                      'Katılımcılar (${event.participantCount})',
                      actionText: event.participantCount > 0 ? 'Tümünü Gör' : null,
                      onAction: () => _showParticipantsSheet(context, participantsAsync),
                    ),
                    const SizedBox(height: 12),
                    _buildParticipantsSection(participantsAsync),
                  ],
                  const SizedBox(height: 24),

                  // Yarış Sonuçları (sadece yarış tipi etkinliklerde göster)
                  if (event.eventType == EventType.race)
                    _buildResultsSection(
                      context: context,
                      resultsAsync: resultsAsync,
                      isAdminOrCoach: isAdminOrCoach,
                      event: event,
                    ),

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomSheet: _isIndividualParticipation(event)
          ? null
          : _buildBottomBar(context, ref, event, rsvpState),
    );
  }

  bool _isIndividualParticipation(EventEntity event) =>
      event.participationType == 'individual';

  Widget _buildInfoRow({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.titleSmall),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.neutral500,
                    ),
                  ),
              ],
            ),
          ),
          if (onTap != null)
            const Icon(Icons.chevron_right, color: AppColors.neutral400),
        ],
      ),
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          splashColor: AppColors.primary.withValues(alpha: 0.1),
          highlightColor: AppColors.primary.withValues(alpha: 0.05),
          child: content,
        ),
      );
    }

    return content;
  }

  Widget _buildSectionHeader(
    String title, {
    String? actionText,
    VoidCallback? onAction,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: AppTypography.titleMedium),
        if (actionText != null)
          TextButton(
            onPressed: onAction,
            child: Text(
              actionText,
              style: AppTypography.labelLarge.copyWith(
                color: AppColors.primary,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildParticipantsSection(
    AsyncValue<List<EventParticipantEntity>> participantsAsync,
  ) {
    return participantsAsync.when(
      data: (participants) {
        if (participants.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.neutral100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.people_outline,
                  color: AppColors.neutral400,
                ),
                const SizedBox(width: 12),
                Text(
                  'Henüz katılımcı yok',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.neutral500,
                  ),
                ),
              ],
            ),
          );
        }

        return Row(
          children: [
            for (int i = 0; i < participants.length && i < 6; i++)
              Transform.translate(
                offset: Offset(-i * 12.0, 0),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: UserAvatar(
                    size: 40,
                    name: participants[i].userName,
                    imageUrl: participants[i].userAvatarUrl,
                  ),
                ),
              ),
            if (participants.length > 6)
              Transform.translate(
                offset: Offset(-6 * 12.0, 0),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.neutral200,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Center(
                    child: Text(
                      '+${participants.length - 6}',
                      style: AppTypography.labelMedium.copyWith(
                        color: AppColors.neutral700,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
      loading: () => const Center(child: LoadingWidget(size: 24)),
      error: (_, __) => const Text('Katılımcılar yüklenemedi'),
    );
  }

  Widget _buildResultsSection({
    required BuildContext context,
    required AsyncValue<List<EventResultEntity>> resultsAsync,
    required bool isAdminOrCoach,
    required EventEntity event,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Yarış Sonuçları',
              style: AppTypography.titleMedium,
            ),
            if (isAdminOrCoach)
              TextButton.icon(
                onPressed: () => _showResultsManagementDialog(context, ref, event),
                icon: const Icon(Icons.settings, size: 18),
                label: const Text('Yönet'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        resultsAsync.when(
          data: (results) {
            if (results.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.neutral100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isAdminOrCoach
                      ? 'Bu yarış için henüz sonuç yüklenmemiş.\nYukarıdaki "Yönet" butonundan şablonu indirip doldurarak sonuçları yükleyebilirsiniz.'
                      : 'Bu yarış için sonuçlar henüz yayınlanmadı.',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.neutral600,
                  ),
                ),
              );
            }

            // Sonuç sayısını göster ve modal açma butonu
            return InkWell(
              onTap: () => _showResultsModal(context, resultsAsync, event),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.emoji_events,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${results.length} Sonuç',
                            style: AppTypography.bodyLarge.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Sıralamayı görüntülemek için dokunun',
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.neutral600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      color: AppColors.neutral400,
                    ),
                  ],
                ),
              ),
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.all(8.0),
            child: LoadingWidget(size: 24),
          ),
          error: (error, _) => Text(
            'Sonuçlar yüklenemedi: $error',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.error,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar(
    BuildContext context,
    WidgetRef ref,
    EventEntity event,
    AsyncValue<void> rsvpState,
  ) {
    final isLoading = rsvpState.isLoading;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: (() {
          // Etkinlik bitmişse hiçbir buton gösterme
          final isEventFinished = event.startTime.add(const Duration(hours: 2)).isBefore(DateTime.now());
          if (isEventFinished) {
            return const SizedBox.shrink();
          }
          
          return event.isUserParticipating
              ? Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.successContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.check_circle,
                              color: AppColors.success,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Katılıyorsunuz',
                              style: AppTypography.labelLarge.copyWith(
                                color: AppColors.success,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    AppButton(
                      text: 'İptal',
                      variant: AppButtonVariant.outlined,
                      isLoading: isLoading,
                      onPressed: () {
                        ref.read(rsvpProvider.notifier).cancelRsvp(widget.eventId);
                      },
                    ),
                  ],
                )
              : AppButton(
                  text: 'Katılıyorum',
                  icon: Icons.check,
                  isLoading: isLoading,
                  isFullWidth: true,
                  onPressed: () {
                    ref.read(rsvpProvider.notifier).rsvp(
                      widget.eventId,
                      RsvpStatus.going,
                    );
                  },
                );
        })(),
      ),
    );
  }

  void _showResultsModal(
    BuildContext context,
    AsyncValue<List<EventResultEntity>> resultsAsync,
    EventEntity event,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) => _ResultsModalContent(
        resultsAsync: resultsAsync,
        initialRankingType: _selectedRankingType,
      ),
    );
  }

  void _showParticipantsSheet(
    BuildContext context,
    AsyncValue<List<EventParticipantEntity>> participantsAsync,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Katılımcılar', style: AppTypography.titleLarge),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: participantsAsync.when(
                data: (participants) => ListView.builder(
                  controller: scrollController,
                  itemCount: participants.length,
                  itemBuilder: (context, index) {
                    final participant = participants[index];
                    return ListTile(
                      leading: UserAvatar(
                        size: 44,
                        name: participant.userName,
                        imageUrl: participant.userAvatarUrl,
                      ),
                      title: Text(participant.userName),
                      subtitle: Text(
                        participant.checkedIn ? 'Katıldı' : 'Gelecek',
                        style: TextStyle(
                          color: participant.checkedIn
                              ? AppColors.success
                              : AppColors.neutral500,
                        ),
                      ),
                      trailing: participant.checkedIn
                          ? const Icon(
                              Icons.check_circle,
                              color: AppColors.success,
                            )
                          : null,
                    );
                  },
                ),
                loading: () => const Center(child: LoadingWidget()),
                error: (_, __) => const Center(
                  child: Text('Katılımcılar yüklenemedi'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSaveAsTemplateDialog(BuildContext context, WidgetRef ref, EventEntity event) {
    final nameController = TextEditingController(text: event.title);
    
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.bookmark_add, color: AppColors.primary),
            const SizedBox(width: 12),
            const Text('Şablon Olarak Kaydet'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Bu etkinliği şablon olarak kaydederek ileride benzer etkinlikleri hızlıca oluşturabilirsiniz.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: 'Şablon Adı',
                hintText: 'Örn: Salı Tempo, Pazar Uzun Koşu',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);

              final templateName = nameController.text.trim();
              if (templateName.isEmpty) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Şablon adı gerekli')),
                );
                return;
              }

              // Aynı isimde şablon var mı kontrol et (isimler büyük/küçük harf duyarsız)
              final templates = ref.read(eventTemplatesProvider).valueOrNull ??
                  await ref.read(eventTemplatesProvider.future);
              final nameExists = (templates ?? []).any(
                (t) => t.name.trim().toLowerCase() == templateName.toLowerCase(),
              );
              if (nameExists) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Aynı isimde bir şablon zaten kayıtlı. Farklı bir isim girin.'),
                    backgroundColor: AppColors.error,
                  ),
                );
                return;
              }

              // Diyaloğu kapat
              navigator.pop();

              // Şablon oluştur
              final template = await ref
                  .read(eventTemplateNotifierProvider.notifier)
                  .createFromEvent(widget.eventId, templateName);

              if (!context.mounted) return;

              if (template != null) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Şablon kaydedildi: ${template.name}'),
                    backgroundColor: AppColors.success,
                  ),
                );
              } else {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Şablon kaydedilemedi'),
                    backgroundColor: AppColors.error,
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

  void _showDeleteConfirmation(BuildContext context, WidgetRef ref) {
    final pageContext = context;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Etkinliği Sil'),
        content: const Text(
          'Bu etkinliği silmek istediğinizden emin misiniz? Bu işlem geri alınamaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                final dataSource = ref.read(eventDataSourceProvider);
                await dataSource.deleteEvent(widget.eventId);
                if (pageContext.mounted) {
                  ref.invalidate(allEventsProvider);
                  ref.invalidate(upcomingEventsProvider);
                  ref.invalidate(thisWeekEventsProvider);
                  ref.invalidate(eventByIdProvider(widget.eventId));
                  pageContext.goNamed(RouteNames.events);
                  ScaffoldMessenger.of(pageContext).showSnackBar(
                    const SnackBar(content: Text('Etkinlik silindi')),
                  );
                }
              } catch (e) {
                if (pageContext.mounted) {
                  ScaffoldMessenger.of(pageContext).showSnackBar(
                    SnackBar(content: Text('Hata: $e')),
                  );
                }
              }
            },
            child: const Text(
              'Sil',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  /// Tekrarlayan etkinlik düzenlenirken: sadece bu / tüm sonrakiler seçimi
  Future<String?> _showRecurringEditScopeDialog(BuildContext context) async {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tekrarlayan etkinliği düzenle'),
        content: const Text(
          'Sadece bu etkinliği mi yoksa bu ve sonraki tüm tekrarları mı güncellemek istiyorsunuz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'only_this'),
            child: const Text('Sadece bu etkinlik'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'all_future'),
            child: const Text('Bu ve sonraki tümü'),
          ),
        ],
      ),
    );
  }

  Widget _buildBannerBackground(
    BuildContext context,
    EventEntity event,
    bool isAdminOrCoach,
    WidgetRef ref,
  ) {
    final hasBanner = event.bannerImageUrl != null && event.bannerImageUrl!.isNotEmpty;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Banner fotoğrafı veya gradient arka plan
        if (hasBanner)
          Image.network(
            event.bannerImageUrl!,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => _buildDefaultBanner(event),
          )
        else
          _buildDefaultBanner(event),

        // Gradient overlay (yazıların okunabilirliği için)
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.5),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),

        // Banner yükleme loading overlay
        if (_isBannerUploading)
          Container(
            color: Colors.black.withValues(alpha: 0.5),
            child: const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          ),

        // BUGÜN etiketi
        if (event.isToday)
          Positioned(
            top: 100,
            left: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.secondary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'BUGÜN',
                style: AppTypography.labelMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

        // Banner değiştirme butonu (Admin/Coach için)
        if (isAdminOrCoach)
          Positioned(
            bottom: 16,
            right: 16,
            child: GestureDetector(
              onTap: () => _showBannerOptions(context, ref, event),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.camera_alt,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      hasBanner ? 'Değiştir' : 'Fotoğraf Ekle',
                      style: AppTypography.labelMedium.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDefaultBanner(EventEntity event) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _getEventTypeColor(event.eventType),
            _getEventTypeColor(event.eventType).withValues(alpha: 0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          _getEventTypeIcon(event.eventType),
          size: 80,
          color: Colors.white.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  void _showBannerOptions(BuildContext context, WidgetRef ref, EventEntity event) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Banner Fotoğrafı', style: AppTypography.titleLarge),
              const SizedBox(height: 20),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.photo_library, color: AppColors.primary),
                ),
                title: const Text('Galeriden Seç'),
                onTap: () {
                  Navigator.pop(context);
                  _pickBannerImage(context, ref, event);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.camera_alt, color: AppColors.secondary),
                ),
                title: const Text('Kamera ile Çek'),
                onTap: () {
                  Navigator.pop(context);
                  _takeBannerPhoto(context, ref, event);
                },
              ),
              if (event.bannerImageUrl != null && event.bannerImageUrl!.isNotEmpty)
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.delete, color: AppColors.error),
                  ),
                  title: const Text('Fotoğrafı Kaldır'),
                  onTap: () {
                    Navigator.pop(context);
                    _removeBannerImage(context, ref, event);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickBannerImage(BuildContext context, WidgetRef ref, EventEntity event) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (!context.mounted) return;

      if (pickedFile != null) {
        await _uploadBannerImage(context, ref, event, pickedFile);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fotoğraf seçilemedi: $e')),
        );
      }
    }
  }

  Future<void> _takeBannerPhoto(BuildContext context, WidgetRef ref, EventEntity event) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (!context.mounted) return;

      if (pickedFile != null) {
        await _uploadBannerImage(context, ref, event, pickedFile);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fotoğraf çekilemedi: $e')),
        );
      }
    }
  }

  Future<void> _uploadBannerImage(BuildContext context, WidgetRef ref, EventEntity event, XFile pickedXFile) async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      // Loading state'i başlat
      if (mounted) {
        setState(() {
          _isBannerUploading = true;
        });
      }

      final fileExt = pickedXFile.name.split('.').last;
      final fileName = 'event_${event.id}_banner_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      final bytes = await pickedXFile.readAsBytes();
      
      // Supabase Storage'a yükle (bytes ile web+mobil uyumlu)
      final supabase = Supabase.instance.client;
      await supabase.storage.from('event-banners').uploadBinary(
        fileName,
        bytes,
        fileOptions: FileOptions(contentType: 'image/$fileExt'),
      );
      
      // Public URL al
      final publicUrl = supabase.storage.from('event-banners').getPublicUrl(fileName);
      
      // Event'i güncelle
      await supabase.from('events').update({
        'banner_image_url': publicUrl,
      }).eq('id', event.id);

      // Provider'ı invalidate et
      ref.invalidate(eventByIdProvider(event.id));
      ref.invalidate(upcomingEventsProvider);
      ref.invalidate(thisWeekEventsProvider);

      // Loading state'i bitir
      if (mounted) {
        setState(() {
          _isBannerUploading = false;
        });
      }

      messenger.showSnackBar(
        const SnackBar(
          content: Text('Banner fotoğrafı güncellendi!'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      // Loading state'i bitir
      if (mounted) {
        setState(() {
          _isBannerUploading = false;
        });
      }

      messenger.showSnackBar(
        SnackBar(content: Text('Yükleme hatası: $e')),
      );
    }
  }

  Future<void> _removeBannerImage(BuildContext context, WidgetRef ref, EventEntity event) async {
    try {
      final supabase = Supabase.instance.client;
      
      // Event'i güncelle
      await supabase.from('events').update({
        'banner_image_url': null,
      }).eq('id', event.id);

      // Provider'ı invalidate et
      ref.invalidate(eventByIdProvider(event.id));
      ref.invalidate(upcomingEventsProvider);
      ref.invalidate(thisWeekEventsProvider);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Banner fotoğrafı kaldırıldı'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    }
  }

  Widget _buildTrainingTypeCard(BuildContext context, EventEntity event, WidgetRef ref) {
    final typeColor = _parseColor(event.trainingTypeColor);
    final userVdot = ref.watch(userVdotProvider);
    
    // Kişisel pace hesapla (offset bazlı)
    String? personalPace;
    if (userVdot != null && userVdot > 0) {
      personalPace = VdotCalculator.formatPaceRange(
        userVdot,
        event.thresholdOffsetMinSeconds,
        event.thresholdOffsetMaxSeconds,
      );
    }
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: typeColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: typeColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.fitness_center,
                  color: typeColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Antrenman Türü',
                      style: AppTypography.labelMedium.copyWith(
                        color: AppColors.neutral500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      event.trainingTypeName!,
                      style: AppTypography.titleMedium.copyWith(
                        color: typeColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (event.trainingTypeDescription != null && 
              event.trainingTypeDescription!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                event.trainingTypeDescription!,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.neutral700,
                  height: 1.5,
                ),
              ),
            ),
          ],
          // Kişisel pace göster
          if (personalPace != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.success.withValues(alpha: 0.15),
                    AppColors.success.withValues(alpha: 0.08),
                  ],
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.speed,
                      size: 18,
                      color: AppColors.success,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Senin Önerilen Pace\'in',
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.neutral600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$personalPace /km',
                          style: AppTypography.titleSmall.copyWith(
                            color: AppColors.success,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ] else if ((userVdot == null || userVdot <= 0) && event.thresholdOffsetMinSeconds != null) ...[
            // VDOT yok, hesapla linki göster (offset'i olan tüm türler için)
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => context.pushNamed(RouteNames.paceCalculator),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.neutral100,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.neutral200,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: AppColors.neutral500,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Kişisel pace önerisi için VDOT hesapla',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.neutral600,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 14,
                      color: AppColors.neutral400,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _parseColor(String? colorHex) {
    if (colorHex == null || colorHex.isEmpty) {
      return AppColors.primary;
    }
    try {
      final hex = colorHex.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return AppColors.primary;
    }
  }

  Color _getEventTypeColor(EventType type) {
    switch (type) {
      case EventType.training:
        return AppColors.secondary;
      case EventType.race:
        return AppColors.error;
      case EventType.social:
        return AppColors.tertiary;
      case EventType.workshop:
        return AppColors.primary;
      case EventType.other:
        return AppColors.neutral600;
    }
  }

  IconData _getEventTypeIcon(EventType type) {
    switch (type) {
      case EventType.training:
        return Icons.directions_run;
      case EventType.race:
        return Icons.emoji_events;
      case EventType.social:
        return Icons.groups;
      case EventType.workshop:
        return Icons.school;
      case EventType.other:
        return Icons.event;
    }
  }

  Widget _buildChatSection(BuildContext context, String eventId, EventEntity event) {
    // Etkinlik bittikten 1 gün sonra chat'e hala erişilebilir ama salt okunur olacak
    final eventEndTime = event.endTime ?? event.startTime.add(const Duration(hours: 2));
    final chatDeadline = eventEndTime.add(const Duration(days: 1));
    final isExpired = DateTime.now().isAfter(chatDeadline);

    return AppCard(
      onTap: () => context.pushNamed(
        RouteNames.eventChat,
        pathParameters: {'eventId': eventId},
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isExpired
                  ? AppColors.neutral200
                  : AppColors.secondaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.chat_bubble_outlined,
              color: isExpired ? AppColors.neutral400 : AppColors.secondary,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Etkinlik Sohbeti',
                  style: AppTypography.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  isExpired
                      ? 'Sohbet artık salt okunur'
                      : 'Katılımcılarla iletişime geç',
                  style: AppTypography.bodySmall.copyWith(
                    color: isExpired ? AppColors.neutral400 : AppColors.neutral600,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isExpired
                  ? AppColors.neutral100
                  : AppColors.secondary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: isExpired ? AppColors.neutral400 : AppColors.secondary,
            ),
          ),
        ],
      ),
    );
  }

  /// Tarih · Saat · Konum/Rota tek kompakt satırda (row)
  Widget _buildCompactDateLocationRow(
    BuildContext context,
    WidgetRef ref,
    EventEntity event,
  ) {
    if (event.routeId != null) {
      final routeAsync = ref.watch(routeByIdProvider(event.routeId!));
      return routeAsync.when(
        data: (route) => _buildOneCompactInfoRow(
          context,
          ref,
          event,
          locationRouteLabel: event.locationName ?? route.name,
          hasRoute: true,
        ),
        loading: () => _buildOneCompactInfoRow(
          context,
          ref,
          event,
          locationRouteLabel: event.locationName ?? '…',
          hasRoute: true,
        ),
        error: (_, __) => _buildOneCompactInfoRow(
          context,
          ref,
          event,
          locationRouteLabel: event.locationName ?? 'Rota',
          hasRoute: true,
        ),
      );
    }
    return _buildOneCompactInfoRow(
      context,
      ref,
      event,
      locationRouteLabel: event.locationName,
      hasRoute: false,
    );
  }

  Widget _buildOneCompactInfoRow(
    BuildContext context,
    WidgetRef ref,
    EventEntity event, {
    required String? locationRouteLabel,
    required bool hasRoute,
  }) {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Tarih
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.neutral500),
            const SizedBox(width: 6),
            Text(
              '${event.dayOfWeek}, ${event.formattedDate}',
              style: AppTypography.bodySmall.copyWith(color: AppColors.neutral700),
            ),
          ],
        ),
        // Saat (bireysel antrenmanda yok)
        if (!_isIndividualParticipation(event))
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.access_time, size: 16, color: AppColors.neutral500),
              const SizedBox(width: 6),
              Text(
                event.formattedTime,
                style: AppTypography.bodySmall.copyWith(color: AppColors.neutral700),
              ),
            ],
          ),
        // Konum / Rota (tıklanınca bottom modal açılır; oradan yol tarifi veya rota detayı)
        if (locationRouteLabel != null && locationRouteLabel.isNotEmpty)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _showLocationRouteSheet(context, ref, event),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.location_on_outlined, size: 16, color: AppColors.neutral500),
                    const SizedBox(width: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 180),
                      child: Text(
                        locationRouteLabel,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Konum/Rota tıklanınca açılan bottom modal (önceki kart tasarımı)
  void _showLocationRouteSheet(
    BuildContext context,
    WidgetRef ref,
    EventEntity event,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) => SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: event.routeId != null
                    ? Consumer(
                        builder: (_, ref, __) {
                          final routeAsync = ref.watch(routeByIdProvider(event.routeId!));
                          void onDirections() {
                            Navigator.pop(modalContext);
                            _openMapsForDirections(
                              event.locationLat,
                              event.locationLng,
                              event.locationName,
                              event.locationAddress,
                            );
                          }
                          void onRouteDetail() {
                            Navigator.pop(modalContext);
                            context.pushNamed(
                              RouteNames.routeDetail,
                              pathParameters: {'routeId': event.routeId!},
                            );
                          }
                          return routeAsync.when(
                            data: (route) {
                              final name = event.locationName ?? route.name;
                              return AppCard(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: AppTypography.titleSmall.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (event.locationAddress != null &&
                                        event.locationAddress!.isNotEmpty &&
                                        event.locationAddress != name) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        event.locationAddress!,
                                        style: AppTypography.bodySmall.copyWith(
                                          color: AppColors.neutral500,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: InkWell(
                                            onTap: onDirections,
                                            borderRadius: BorderRadius.circular(8),
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 8),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.directions, size: 20, color: AppColors.primary),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    'Yol Tarifi Al',
                                                    style: AppTypography.labelMedium.copyWith(
                                                      color: AppColors.primary,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        InkWell(
                                          onTap: onRouteDetail,
                                          borderRadius: BorderRadius.circular(8),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 8),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  'Rotayı Görüntüle',
                                                  style: AppTypography.labelMedium.copyWith(
                                                    color: AppColors.primary,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                Icon(Icons.chevron_right, size: 18, color: AppColors.primary),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        Icon(Icons.straighten, size: 14, color: AppColors.neutral500),
                                        Text(
                                          route.formattedDistance,
                                          style: AppTypography.bodySmall.copyWith(color: AppColors.neutral500),
                                        ),
                                        Icon(Icons.trending_up, size: 14, color: AppColors.neutral500),
                                        Text(
                                          route.formattedElevationGain,
                                          style: AppTypography.bodySmall.copyWith(color: AppColors.neutral500),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppColors.tertiary.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            route.terrainType.displayName,
                                            style: AppTypography.labelSmall.copyWith(color: AppColors.tertiary),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                            loading: () => AppCard(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Row(
                                  children: [
                                    Icon(Icons.location_on_outlined, color: AppColors.neutral400, size: 24),
                                    const SizedBox(width: 12),
                                    const Expanded(
                                      child: SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            error: (_, __) => AppCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    event.locationName ?? 'Konum',
                                    style: AppTypography.titleSmall,
                                  ),
                                  const SizedBox(height: 12),
                                  InkWell(
                                    onTap: onDirections,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      child: Text(
                                        'Yol Tarifi Al',
                                        style: AppTypography.labelMedium.copyWith(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                  InkWell(
                                    onTap: onRouteDetail,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      child: Row(
                                        children: [
                                          Text(
                                            'Rotayı görüntüle',
                                            style: AppTypography.bodyMedium.copyWith(color: AppColors.primary),
                                          ),
                                          const SizedBox(width: 4),
                                          Icon(Icons.chevron_right, size: 18, color: AppColors.primary),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      )
                    : AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              event.locationName ?? 'Konum',
                              style: AppTypography.titleSmall.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (event.locationAddress != null &&
                                event.locationAddress!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                event.locationAddress!,
                                style: AppTypography.bodySmall.copyWith(
                                  color: AppColors.neutral500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            const SizedBox(height: 12),
                            InkWell(
                              onTap: () {
                                Navigator.pop(modalContext);
                                _openMapsForDirections(
                                  event.locationLat,
                                  event.locationLng,
                                  event.locationName,
                                  event.locationAddress,
                                );
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.directions, size: 20, color: AppColors.primary),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Yol Tarifi Al',
                                      style: AppTypography.labelMedium.copyWith(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Harita uygulamasında yol tarifi açar
  /// Android'de Google Maps, iOS'ta Apple Maps kullanır
  Future<void> _openMapsForDirections(
    double? lat,
    double? lng,
    String? locationName,
    String? locationAddress,
  ) async {
    String url;
    
    // Önce koordinatları kullan, yoksa adresi kullan
    final hasCoordinates = lat != null && lng != null;
    final fullAddress = locationAddress != null && locationAddress.isNotEmpty
        ? locationAddress
        : locationName;
    
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      // iOS için Apple Maps yol tarifi URL'i
      if (hasCoordinates) {
        url = 'http://maps.apple.com/?daddr=$lat,$lng';
      } else if (fullAddress != null && fullAddress.isNotEmpty) {
        // iOS'ta adres için query parametresi kullan
        final encodedAddress = Uri.encodeComponent(fullAddress);
        url = 'http://maps.apple.com/?q=$encodedAddress';
      } else {
        // Hiçbir şey yoksa çık
        return;
      }
    } else {
      // Android, Web ve diğer platformlar için Google Maps URL'i
      if (hasCoordinates) {
        url = 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng';
      } else if (fullAddress != null && fullAddress.isNotEmpty) {
        final encodedAddress = Uri.encodeComponent(fullAddress);
        url = 'https://www.google.com/maps/dir/?api=1&destination=$encodedAddress';
      } else {
        return;
      }
    }

    final uri = Uri.parse(url);
    
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      } else {
        // Eğer harita uygulaması açılamazsa, genel bir web URL'i dene
        final fallbackUrl = hasCoordinates
            ? 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng'
            : (fullAddress != null && fullAddress.isNotEmpty
                ? 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(fullAddress)}'
                : null);
        
        if (fallbackUrl != null) {
          final webUri = Uri.parse(fallbackUrl);
          if (await canLaunchUrl(webUri)) {
            await launchUrl(webUri, mode: LaunchMode.externalApplication);
          }
        }
      }
    } catch (e) {
      // Hata durumunda sessizce başarısız ol
    }
  }

  /// Yarış sonuçları yönetim dialog'u (şablon indir / sonuç yükle)
  void _showResultsManagementDialog(
    BuildContext context,
    WidgetRef ref,
    EventEntity event,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (dialogContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Yarış Sonuçları Yönetimi',
                style: AppTypography.titleLarge,
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.download, color: AppColors.primary),
                ),
                title: const Text('Şablonu İndir / Paylaş'),
                subtitle: const Text(
                  'Katılımcı listesiyle dolu Excel şablonunu indirip doldurun',
                ),
                onTap: () {
                  Navigator.pop(dialogContext);
                  _downloadResultsTemplate(context, ref, event);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.upload, color: AppColors.secondary),
                ),
                title: const Text('Sonuçları İçe Aktar'),
                subtitle: const Text(
                  'Doldurduğunuz Excel dosyasını yükleyin',
                ),
                onTap: () {
                  Navigator.pop(dialogContext);
                  _importResults(context, ref, event);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Şablon indirme ve paylaşma
  Future<void> _downloadResultsTemplate(
    BuildContext context,
    WidgetRef ref,
    EventEntity event,
  ) async {
    
    try {
      // Loading göster
      if (!context.mounted) {
        return;
      }

      // Async sonrasında context kullanmamak için Navigator referansını al
      final navigator = Navigator.of(context);

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      final repo = ref.read(eventResultsRepositoryProvider);
      final result = await repo.downloadResultsTemplate(event.id);
      
      // Loading dialog'u kapat
      try {
        navigator.pop();
      } catch (_) {
        // Dialog zaten kapatılmış veya navigasyon değişmiş olabilir
      }

      if (!context.mounted) {
        return;
      }

      if (result.failure != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Şablon indirilemedi: ${result.failure!.message}'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }

      final bytes = result.bytes;
      if (bytes == null || bytes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Şablon indirilemedi: Boş dosya'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }

      // Dosya adını temizle - özel karakterleri kaldır
      final cleanTitle = event.title
          .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_') // Dosya adında geçersiz karakterler
          .replaceAll(RegExp(r'\s+'), ' ') // Çoklu boşlukları tek boşluğa çevir
          .trim();
      final fileName = '$cleanTitle - Yarış Sonuçları Şablonu.xlsx';

      if (kIsWeb) {
        // Web'de XFile.fromData ile paylaş (download)
        final xFile = XFile.fromData(
          Uint8List.fromList(bytes),
          name: fileName,
          mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );

        // Context'i kontrol et
        if (!context.mounted) return;

        await Share.shareXFiles(
          [xFile],
          subject: '${event.title} - Yarış Sonuçları Şablonu',
        );
      } else {
        // Mobilde: geçici dosya oluştur
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/$fileName');
        await file.writeAsBytes(Uint8List.fromList(bytes));

        // Context'i kontrol et
        if (!context.mounted) return;

        // Loading dialog kapatıldıktan sonra UI'nin güncellenmesi için kısa bir bekleme
        await Future.delayed(const Duration(milliseconds: 100));

        // Context'i tekrar kontrol et
        if (!context.mounted) return;

        // iOS için sharePositionOrigin gerekli
        final size = MediaQuery.of(context).size;
        final shareOrigin = Rect.fromLTWH(
          size.width / 2 - 1,
          size.height / 2 - 1,
          2,
          2,
        );

        await Share.shareXFiles(
          [XFile(file.path)],
          subject: '${event.title} - Yarış Sonuçları Şablonu',
          sharePositionOrigin: shareOrigin,
        );
      }
    } catch (e) {
      // Loading dialog'u kapatmayı dene (eğer açıksa)
      if (context.mounted) {
        try {
          Navigator.of(context, rootNavigator: false).pop();
        } catch (_) {
          // Dialog zaten kapatılmış veya yok
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Şablon indirme hatası: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// Sonuçları içe aktarma
  Future<void> _importResults(
    BuildContext context,
    WidgetRef ref,
    EventEntity event,
  ) async {
    try {
      // Dosya seç
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        return; // Kullanıcı iptal etti
      }

      final pickedFile = result.files.single;
      final fileName = pickedFile.name;
      // Web'de bytes doğrudan gelir, mobilde path üzerinden okunur
      final Uint8List fileBytes;
      if (pickedFile.bytes != null) {
        fileBytes = pickedFile.bytes!;
      } else if (!kIsWeb && pickedFile.path != null) {
        final file = File(pickedFile.path!);
        fileBytes = await file.readAsBytes();
      } else {
        return; // Dosya okunamadı
      }

      // Loading göster
      if (!context.mounted) return;

      // Async sonrasında context kullanmamak için Navigator referansını al
      final navigator = Navigator.of(context, rootNavigator: true);

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      final repo = ref.read(eventResultsRepositoryProvider);
      final importResult = await repo.importResults(
        eventId: event.id,
        fileBytes: fileBytes.toList(),
        fileName: fileName,
      );

      // Loading dialog'u kapat
      try {
        navigator.pop();
      } catch (_) {
        // Dialog zaten kapatılmış veya navigasyon değişmiş olabilir
      }

      // Kısa bir gecikme ekle - UI'nin güncellenmesi için
      await Future.delayed(const Duration(milliseconds: 100));

      if (!context.mounted) return;

      if (importResult.failure != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import başarısız: ${importResult.failure!.message}'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }

      // Sonuçları göster
      final errors = importResult.errors;
      if (errors.isNotEmpty) {
        _showImportErrorsDialog(context, errors);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${importResult.success ? "Başarıyla" : "Kısmen"} import edildi',
            ),
            backgroundColor: importResult.success
                ? AppColors.success
                : AppColors.warning,
          ),
        );
      }

      // Sonuçları yenile
      ref.invalidate(eventResultsProvider(event.id));
    } catch (e) {
      // Loading dialog'u kapatmayı dene (eğer açıksa)
      if (context.mounted) {
        try {
          Navigator.of(context, rootNavigator: false).pop();
        } catch (_) {
          // Dialog zaten kapatılmış veya yok
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// Import hatalarını gösteren dialog
  void _showImportErrorsDialog(
    BuildContext context,
    List<ImportRowError> errors,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning, color: AppColors.warning),
            const SizedBox(width: 8),
            Text('${errors.length} Satırda Hata'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: errors.length,
            itemBuilder: (ctx, index) {
              final error = errors[index];
              return ListTile(
                dense: true,
                leading: Text(
                  '${error.rowIndex}',
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.error,
                  ),
                ),
                title: Text(
                  error.message,
                  style: AppTypography.bodySmall,
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }
}

/// Modal içeriği için ayrı StatefulWidget
class _ResultsModalContent extends StatefulWidget {
  final AsyncValue<List<EventResultEntity>> resultsAsync;
  final String initialRankingType;

  const _ResultsModalContent({
    required this.resultsAsync,
    required this.initialRankingType,
  });

  @override
  State<_ResultsModalContent> createState() => _ResultsModalContentState();
}

class _ResultsModalContentState extends State<_ResultsModalContent> {
  late String _selectedRankingType;

  @override
  void initState() {
    super.initState();
    _selectedRankingType = widget.initialRankingType;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Yarış Sonuçları',
                  style: AppTypography.titleLarge,
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Content
          Expanded(
            child: widget.resultsAsync.when(
              data: (results) {
                if (results.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Sonuç bulunamadı',
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.neutral500,
                        ),
                      ),
                    ),
                  );
                }

                // Filtreleme: Seçilen sıralama tipine göre
                List<EventResultEntity> filteredResults = results;
                
                if (_selectedRankingType == 'female') {
                  filteredResults = results
                      .where((r) => r.gender?.toLowerCase() == 'f' || 
                                   r.gender?.toLowerCase() == 'female' ||
                                   r.gender?.toLowerCase() == 'kadın' ||
                                   r.gender?.toLowerCase() == 'k')
                      .toList();
                } else if (_selectedRankingType == 'male') {
                  filteredResults = results
                      .where((r) => r.gender?.toLowerCase() == 'm' || 
                                   r.gender?.toLowerCase() == 'male' ||
                                   r.gender?.toLowerCase() == 'erkek' ||
                                   r.gender?.toLowerCase() == 'e')
                      .toList();
                }

                // Sıralama: Her zaman süreye göre (en hızlıdan en yavaşa)
                filteredResults.sort((a, b) {
                  final aTime = a.finishTimeSeconds ?? 999999;
                  final bTime = b.finishTimeSeconds ?? 999999;
                  return aTime.compareTo(bTime);
                });

                return Column(
                  children: [
                    // Dropdown ile sıralama tipi seçimi
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.neutral100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.neutral300),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedRankingType,
                            isExpanded: true,
                            icon: const Icon(Icons.arrow_drop_down, color: AppColors.neutral600),
                            style: AppTypography.bodyMedium.copyWith(
                              color: AppColors.neutral900,
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'overall',
                                child: Text('Genel Sıralama'),
                              ),
                              DropdownMenuItem(
                                value: 'male',
                                child: Text('Erkekler Sıralaması'),
                              ),
                              DropdownMenuItem(
                                value: 'female',
                                child: Text('Kadınlar Sıralaması'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _selectedRankingType = value;
                                });
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                    // Liste
                    Expanded(
                      child: filteredResults.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  'Bu kategoride sonuç bulunamadı',
                                  style: AppTypography.bodyMedium.copyWith(
                                    color: AppColors.neutral500,
                                  ),
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: filteredResults.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final r = filteredResults[index];
                                final rank = index + 1;
                                
                                // İlk 3 için özel renkler
                                Color rankColor = AppColors.neutral400;
                                Color rankBgColor = AppColors.neutral100;
                                if (rank == 1) {
                                  rankColor = const Color(0xFFFFD700);
                                  rankBgColor = const Color(0xFFFFF8DC);
                                } else if (rank == 2) {
                                  rankColor = const Color(0xFFC0C0C0);
                                  rankBgColor = const Color(0xFFF5F5F5);
                                } else if (rank == 3) {
                                  rankColor = const Color(0xFFCD7F32);
                                  rankBgColor = const Color(0xFFFFF4E6);
                                }

                                return Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: rank <= 3 ? rankColor.withValues(alpha: 0.3) : AppColors.neutral200,
                                      width: rank <= 3 ? 2 : 1,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.neutral200.withValues(alpha: 0.3),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      // Sıralama numarası
                                      Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          color: rank <= 3 ? rankBgColor : AppColors.neutral100,
                                          shape: BoxShape.circle,
                                          border: rank <= 3
                                              ? Border.all(color: rankColor, width: 2)
                                              : null,
                                        ),
                                        child: Center(
                                          child: Text(
                                            rank.toString(),
                                            style: AppTypography.titleMedium.copyWith(
                                              color: rank <= 3 ? rankColor : AppColors.neutral700,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      // Avatar ve isim
                                      Expanded(
                                        child: Row(
                                          children: [
                                            if (r.avatarUrl != null && r.avatarUrl!.isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(right: 12),
                                                child: UserAvatar(
                                                  size: 40,
                                                  name: r.fullName,
                                                  imageUrl: r.avatarUrl,
                                                ),
                                              ),
                                            Expanded(
                                              child: Text(
                                                r.fullName,
                                                style: AppTypography.bodyLarge.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Süre
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            r.formattedFinishTime ?? '-',
                                            style: AppTypography.titleMedium.copyWith(
                                              fontFeatures: const [FontFeature.tabularFigures()],
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.neutral900,
                                            ),
                                          ),
                                          if (rank <= 3) ...[
                                            const SizedBox(height: 4),
                                            Icon(
                                              rank == 1
                                                  ? Icons.emoji_events
                                                  : rank == 2
                                                      ? Icons.workspace_premium
                                                      : Icons.stars,
                                              color: rankColor,
                                              size: 16,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
              loading: () => const Center(child: LoadingWidget()),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Sonuçlar yüklenemedi: $error',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.error,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
