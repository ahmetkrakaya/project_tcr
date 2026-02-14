import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../shared/providers/auth_provider.dart';
import '../../data/datasources/event_remote_datasource.dart';
import '../../data/models/event_info_block_model.dart';
import '../../data/models/event_report_model.dart';
import '../../data/models/event_activity_stat_model.dart';
import '../../data/models/user_activity_report_model.dart';
import '../../domain/entities/event_entity.dart';
import '../../domain/entities/event_info_block_entity.dart';
import '../../domain/entities/event_template_entity.dart';
import '../../domain/entities/event_result_entity.dart';
import '../../domain/repositories/event_results_repository.dart';
import '../../data/repositories/event_results_repository_impl.dart';
import '../../../posts/data/datasources/post_remote_datasource.dart';
import '../../../posts/data/models/post_block_model.dart';
import '../../../posts/data/models/post_model.dart';
import '../../../posts/presentation/providers/post_provider.dart';

/// Event info block -> post block dönüşümü (kaydetme için)
PostBlockModel eventInfoBlockToPostBlock(
  EventInfoBlockModel block,
  String postId,
  int orderIndex,
) {
  return PostBlockModel(
    id: '',
    postId: postId,
    type: block.type,
    content: block.content,
    subContent: block.subContent,
    imageUrl: null,
    color: block.color,
    icon: block.icon,
    orderIndex: orderIndex,
    createdAt: block.createdAt,
    updatedAt: block.updatedAt,
  );
}

/// Post block -> event info block entity (okuma için; event tarafında image yok, text sayılır)
EventInfoBlockEntity postBlockToEventInfoBlockEntity(
  PostBlockModel block,
  String eventId,
) {
  final typeStr = block.type == 'image' ? 'text' : block.type;
  return EventInfoBlockEntity(
    id: block.id,
    eventId: eventId,
    type: EventInfoBlockType.fromString(typeStr),
    content: block.content,
    subContent: block.subContent,
    color: block.color,
    icon: block.icon,
    orderIndex: block.orderIndex,
    createdAt: block.createdAt,
    updatedAt: block.updatedAt,
  );
}

/// Supabase client provider
final _supabaseProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Event datasource provider
final eventDataSourceProvider = Provider<EventRemoteDataSource>((ref) {
  return EventRemoteDataSourceImpl(ref.watch(_supabaseProvider));
});

/// Event results repository provider
final eventResultsRepositoryProvider = Provider<EventResultsRepository>((ref) {
  final supabase = ref.watch(_supabaseProvider);
  return EventResultsRepositoryImpl(supabase);
});

/// Upcoming Events State
class UpcomingEventsState {
  final List<EventEntity> events;
  final bool isLoading;
  final String? error;

  const UpcomingEventsState({
    this.events = const [],
    this.isLoading = false,
    this.error,
  });

  UpcomingEventsState copyWith({
    List<EventEntity>? events,
    bool? isLoading,
    String? error,
  }) {
    return UpcomingEventsState(
      events: events ?? this.events,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// Upcoming Events Notifier
class UpcomingEventsNotifier extends StateNotifier<UpcomingEventsState> {
  final EventRemoteDataSource _dataSource;

  UpcomingEventsNotifier(this._dataSource) : super(const UpcomingEventsState());

  Future<void> loadEvents() async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, error: null);

    try {
      final models = await _dataSource.getUpcomingEvents();
      final events = models.map((m) => m.toEntity()).toList();

      state = state.copyWith(
        events: events,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> refresh() async {
    state = const UpcomingEventsState();
    await loadEvents();
  }
}

/// Upcoming Events Provider
/// Kullanıcı ID'sine bağlı - kullanıcı değiştiğinde otomatik yeniden yüklenir
final upcomingEventsProvider = StateNotifierProvider<UpcomingEventsNotifier, UpcomingEventsState>((ref) {
  // Kullanıcı ID'sini watch et - kullanıcı değiştiğinde provider yeniden yüklenir
  ref.watch(userIdProvider);
  final dataSource = ref.watch(eventDataSourceProvider);
  return UpcomingEventsNotifier(dataSource);
});

/// This Week Events Provider
/// Kullanıcı ID'sine bağlı - kullanıcı değiştiğinde otomatik yeniden yüklenir
final thisWeekEventsProvider = FutureProvider<List<EventEntity>>((ref) async {
  // Kullanıcı ID'sini watch et - kullanıcı değiştiğinde provider yeniden yüklenir
  ref.watch(userIdProvider);
  final dataSource = ref.watch(eventDataSourceProvider);
  final models = await dataSource.getThisWeekEvents();
  return models.map((m) => m.toEntity()).toList();
});

/// All Events Provider
/// Kullanıcı ID'sine bağlı - kullanıcı değiştiğinde otomatik yeniden yüklenir
final allEventsProvider = FutureProvider<List<EventEntity>>((ref) async {
  // Kullanıcı ID'sini watch et - kullanıcı değiştiğinde provider yeniden yüklenir
  ref.watch(userIdProvider);
  final dataSource = ref.watch(eventDataSourceProvider);
  final models = await dataSource.getAllEvents();
  return models.map((m) => m.toEntity()).toList();
});

/// Single Event Provider
final eventByIdProvider = FutureProvider.family<EventEntity, String>((ref, eventId) async {
  final dataSource = ref.watch(eventDataSourceProvider);
  final model = await dataSource.getEventById(eventId);
  return model.toEntity();
});

/// Event Participants Provider
final eventParticipantsProvider = FutureProvider.family<List<EventParticipantEntity>, String>((ref, eventId) async {
  final dataSource = ref.watch(eventDataSourceProvider);
  final models = await dataSource.getEventParticipants(eventId);
  return models.map((m) => m.toEntity()).toList();
});

/// Event results provider (yarış sonuçları)
final eventResultsProvider = FutureProvider.family<List<EventResultEntity>, String>((ref, eventId) async {
  final repo = ref.watch(eventResultsRepositoryProvider);
  final result = await repo.getEventResults(eventId);
  if (result.failure != null) {
    throw result.failure!;
  }
  return result.results ?? <EventResultEntity>[];
});

/// User Events Provider (events user is participating)
final userEventsProvider = FutureProvider.family<List<EventEntity>, String>((ref, userId) async {
  final dataSource = ref.watch(eventDataSourceProvider);
  final models = await dataSource.getUserEvents(userId);
  return models.map((m) => m.toEntity()).toList();
});

/// Current User Events Provider
final currentUserEventsProvider = FutureProvider<List<EventEntity>>((ref) async {
  final supabase = ref.watch(_supabaseProvider);
  final user = supabase.auth.currentUser;
  if (user == null) return [];

  final dataSource = ref.watch(eventDataSourceProvider);
  final models = await dataSource.getUserEvents(user.id);
  return models.map((m) => m.toEntity()).toList();
});

/// Training Groups Provider
final trainingGroupsProvider = FutureProvider<List<TrainingGroupEntity>>((ref) async {
  final dataSource = ref.watch(eventDataSourceProvider);
  final models = await dataSource.getTrainingGroups();
  return models.map((m) => m.toEntity()).toList();
});

/// Training Types Provider (Antrenman Türleri)
final trainingTypesProvider = FutureProvider<List<TrainingTypeEntity>>((ref) async {
  final dataSource = ref.watch(eventDataSourceProvider);
  final models = await dataSource.getTrainingTypes();
  return models.map((m) => m.toEntity()).toList();
});

/// RSVP Notifier for handling event participation
class RsvpNotifier extends StateNotifier<AsyncValue<void>> {
  final EventRemoteDataSource _dataSource;
  final Ref _ref;

  RsvpNotifier(this._dataSource, this._ref) : super(const AsyncValue.data(null));

  Future<void> rsvp(String eventId, RsvpStatus status, {String? note}) async {
    state = const AsyncValue.loading();
    try {
      await _dataSource.rsvpToEvent(eventId, status.toDbString(), note: note);
      state = const AsyncValue.data(null);
      // Refresh related providers
      _ref.invalidate(eventByIdProvider(eventId));
      _ref.invalidate(eventParticipantsProvider(eventId));
      _ref.invalidate(currentUserEventsProvider);
      _ref.invalidate(upcomingEventsProvider);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> cancelRsvp(String eventId) async {
    state = const AsyncValue.loading();
    try {
      await _dataSource.cancelRsvp(eventId);
      state = const AsyncValue.data(null);
      // Refresh related providers
      _ref.invalidate(eventByIdProvider(eventId));
      _ref.invalidate(eventParticipantsProvider(eventId));
      _ref.invalidate(currentUserEventsProvider);
      _ref.invalidate(upcomingEventsProvider);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

/// RSVP Provider
final rsvpProvider = StateNotifierProvider<RsvpNotifier, AsyncValue<void>>((ref) {
  final dataSource = ref.watch(eventDataSourceProvider);
  return RsvpNotifier(dataSource, ref);
});

// ========== Event Info Blocks Providers ==========

/// Event Info Blocks Provider — veriyi event_id'li post'un post_blocks'undan verir (tek kaynak)
final eventInfoBlocksProvider = FutureProvider.family<List<EventInfoBlockEntity>, String>((ref, eventId) async {
  final postDs = ref.watch(postDataSourceProvider);
  final post = await postDs.getPostByEventId(eventId);
  if (post == null) return [];
  final blocks = await postDs.getPostBlocks(post.id);
  return blocks.map((b) => postBlockToEventInfoBlockEntity(b, eventId)).toList();
});

/// Event Info Blocks Notifier - sadece post_blocks'a yazar; veri tek kaynak (post)
class EventInfoBlocksNotifier extends StateNotifier<AsyncValue<List<EventInfoBlockEntity>>> {
  final EventRemoteDataSource _eventDataSource;
  final PostRemoteDataSource _postDataSource;
  final Ref _ref;
  final String eventId;

  EventInfoBlocksNotifier(this._eventDataSource, this._postDataSource, this._ref, this.eventId)
      : super(const AsyncValue.loading()) {
    loadBlocks();
  }

  Future<void> loadBlocks() async {
    state = const AsyncValue.loading();
    try {
      final post = await _postDataSource.getPostByEventId(eventId);
      if (post == null) {
        state = const AsyncValue.data([]);
        return;
      }
      final blockModels = await _postDataSource.getPostBlocks(post.id);
      final blocks = blockModels.map((b) => postBlockToEventInfoBlockEntity(b, eventId)).toList();
      state = AsyncValue.data(blocks);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Sadece yerel state günceller; kaydetmek için [saveBlocks] kullanın.
  void addBlock(EventInfoBlockType type, String content, {String? subContent, String? color}) {
    final currentBlocks = state.valueOrNull ?? [];
    final newOrderIndex = currentBlocks.length;
    final entity = EventInfoBlockEntity(
      id: '', // Kaydetmede sunucu atayacak
      eventId: eventId,
      type: type,
      content: content,
      subContent: subContent,
      color: color,
      orderIndex: newOrderIndex,
      createdAt: DateTime.now(),
    );
    state = AsyncValue.data([...currentBlocks, entity]);
  }

  /// Sadece yerel state günceller; kaydetmek için [saveBlocks] kullanın.
  void updateBlock(EventInfoBlockEntity block) {
    final currentBlocks = state.valueOrNull ?? [];
    final updatedBlocks = currentBlocks.map((b) {
      if (b.id == block.id) return block;
      return b;
    }).toList();
    state = AsyncValue.data(updatedBlocks);
  }

  /// Sadece yerel state günceller; kaydetmek için [saveBlocks] kullanın.
  void deleteBlock(String blockId) {
    final currentBlocks = state.valueOrNull ?? [];
    state = AsyncValue.data(currentBlocks.where((b) => b.id != blockId).toList());
  }

  /// Sadece yerel state günceller; kaydetmek için [saveBlocks] kullanın.
  void reorderBlocks(int oldIndex, int newIndex) {
    final currentBlocks = List<EventInfoBlockEntity>.from(state.valueOrNull ?? []);
    if (oldIndex < newIndex) newIndex -= 1;
    final block = currentBlocks.removeAt(oldIndex);
    currentBlocks.insert(newIndex, block);
    state = AsyncValue.data(currentBlocks);
  }

  /// Tüm blokları sadece post_blocks'a yazar (tek kaynak; event_info_blocks kullanılmaz).
  Future<bool> saveBlocks() async {
    final blocks = state.valueOrNull ?? [];
    state = const AsyncValue.loading();
    try {
      final event = await _eventDataSource.getEventById(eventId);
      PostModel? existingPost = await _postDataSource.getPostByEventId(eventId);
      PostModel post;
      if (existingPost != null) {
        post = existingPost;
        await _postDataSource.updatePost(PostModel(
          id: post.id,
          userId: post.userId,
          title: event.title,
          coverImageUrl: event.bannerImageUrl ?? post.coverImageUrl,
          isPublished: post.isPublished,
          blocks: post.blocks,
          createdAt: post.createdAt,
          updatedAt: DateTime.now(),
          isPinned: post.isPinned,
          pinnedAt: post.pinnedAt,
          eventId: post.eventId,
        ));
      } else {
        post = await _postDataSource.createPost(PostModel(
          id: '',
          userId: '',
          title: event.title,
          coverImageUrl: event.bannerImageUrl,
          eventId: eventId,
          isPublished: true,
          createdAt: DateTime.now(),
        ));
      }
      await _postDataSource.deleteAllPostBlocks(post.id);
      final postBlocks = <PostBlockModel>[];
      for (int i = 0; i < blocks.length; i++) {
        final e = blocks[i];
        final model = EventInfoBlockModel(
          id: '',
          eventId: eventId,
          type: e.type.toDbString(),
          content: e.content,
          subContent: e.subContent,
          color: e.color,
          icon: e.icon,
          orderIndex: i,
          createdAt: e.createdAt,
        );
        postBlocks.add(eventInfoBlockToPostBlock(model, post.id, i));
      }
      if (postBlocks.isNotEmpty) {
        await _postDataSource.createPostBlocks(post.id, postBlocks);
      }
      await loadBlocks();
      _ref.invalidate(eventInfoBlocksProvider(eventId));
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  void refresh() {
    _ref.invalidate(eventInfoBlocksProvider(eventId));
    loadBlocks();
  }
}

/// Event Info Blocks Notifier Provider
final eventInfoBlocksNotifierProvider = StateNotifierProvider.family<
    EventInfoBlocksNotifier,
    AsyncValue<List<EventInfoBlockEntity>>,
    String>((ref, eventId) {
  final eventDs = ref.watch(eventDataSourceProvider);
  final postDs = ref.watch(postDataSourceProvider);
  return EventInfoBlocksNotifier(eventDs, postDs, ref, eventId);
});

// ========== Event Templates Providers ==========

/// Event Templates Provider - Tüm şablonları getirir
final eventTemplatesProvider = FutureProvider<List<EventTemplateEntity>>((ref) async {
  final dataSource = ref.watch(eventDataSourceProvider);
  final models = await dataSource.getEventTemplates();
  return models.map((m) => m.toEntity()).toList();
});

/// Single Event Template Provider
final eventTemplateByIdProvider = FutureProvider.family<EventTemplateEntity, String>((ref, templateId) async {
  final dataSource = ref.watch(eventDataSourceProvider);
  final model = await dataSource.getEventTemplateById(templateId);
  return model.toEntity();
});

/// Event Template Notifier - Şablon CRUD işlemleri
class EventTemplateNotifier extends StateNotifier<AsyncValue<void>> {
  final EventRemoteDataSource _dataSource;
  final Ref _ref;

  EventTemplateNotifier(this._dataSource, this._ref) : super(const AsyncValue.data(null));

  /// Mevcut etkinlikten şablon oluştur
  Future<EventTemplateEntity?> createFromEvent(String eventId, String templateName) async {
    state = const AsyncValue.loading();
    try {
      final model = await _dataSource.createTemplateFromEvent(eventId, templateName);
      state = const AsyncValue.data(null);
      
      // Şablon listesini güncelle
      _ref.invalidate(eventTemplatesProvider);
      
      return model.toEntity();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return null;
    }
  }

  /// Şablon sil
  Future<void> deleteTemplate(String templateId) async {
    state = const AsyncValue.loading();
    try {
      await _dataSource.deleteEventTemplate(templateId);
      state = const AsyncValue.data(null);
      
      // Şablon listesini güncelle
      _ref.invalidate(eventTemplatesProvider);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

/// Event Template Notifier Provider
final eventTemplateNotifierProvider = StateNotifierProvider<EventTemplateNotifier, AsyncValue<void>>((ref) {
  final dataSource = ref.watch(eventDataSourceProvider);
  return EventTemplateNotifier(dataSource, ref);
});

/// Event Report Provider
final eventReportProvider = FutureProvider.family<EventReportSummaryModel, ({DateTime startDate, DateTime endDate, String? eventType, String? groupId})>((ref, params) async {
  final dataSource = ref.watch(eventDataSourceProvider);
  final result = await dataSource.getEventReport(
    startDate: params.startDate,
    endDate: params.endDate,
    eventType: params.eventType,
    groupId: params.groupId,
  );
  return EventReportSummaryModel.fromJson(result);
});

/// Event Activity Stats Provider (event bazında kullanıcı istatistikleri)
final eventActivityStatsProvider = FutureProvider.family<List<EventActivityStatModel>, String>((ref, eventId) async {
  final dataSource = ref.watch(eventDataSourceProvider);
  return dataSource.getEventActivityStats(eventId);
});

/// Grup Raporu Provider
final groupReportProvider = FutureProvider.family<Map<String, dynamic>, ({String groupId, DateTime startDate, DateTime endDate})>((ref, params) async {
  final dataSource = ref.watch(eventDataSourceProvider);
  return dataSource.getGroupReport(
    groupId: params.groupId,
    startDate: params.startDate,
    endDate: params.endDate,
  );
});

/// Kullanıcı Aktivite Raporu Provider
final userActivityReportProvider = FutureProvider.family<
    List<UserActivityReportModel>,
    ({
      String userId,
      DateTime startDate,
      DateTime endDate,
    })>((ref, params) async {
  final dataSource = ref.watch(eventDataSourceProvider);
  return dataSource.getUserActivityReport(
    userId: params.userId,
    startDate: params.startDate,
    endDate: params.endDate,
  );
});
