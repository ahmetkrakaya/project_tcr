import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../events/presentation/providers/event_provider.dart'
    show
        allEventsProvider,
        eventByIdProvider,
        eventParticipantsProvider,
        upcomingEventsProvider;
import '../../../marketplace/presentation/providers/marketplace_provider.dart'
    show ReportDateRange;
import '../../data/datasources/finance_remote_datasource.dart';
import '../../data/models/event_finance_model.dart';
import '../../data/models/finance_report_model.dart';

final financeDataSourceProvider = Provider<FinanceRemoteDataSource>((ref) {
  return FinanceRemoteDataSourceImpl(Supabase.instance.client);
});

/// Etkinliğin ücret ayarları (etkinlik formu için)
final eventFinanceSettingsProvider =
    FutureProvider.family<EventFinanceSettings?, String>((ref, eventId) async {
  return ref.watch(financeDataSourceProvider).getEventFinanceSettings(eventId);
});

/// Etkinlik finans detayı: özet + katılımcı satışları
final eventFinanceDetailProvider =
    FutureProvider.family<EventFinanceDetail, String>((ref, eventId) async {
  return ref.watch(financeDataSourceProvider).getEventFinanceDetail(eventId);
});

/// Etkinlik bazlı finans özeti
final eventFinanceOverviewProvider =
    FutureProvider.family<List<EventFinanceOverviewRow>, ReportDateRange>(
        (ref, range) async {
  return ref
      .watch(financeDataSourceProvider)
      .getEventFinanceOverview(from: range.from, to: range.to);
});

/// Genel kasa raporu (market + etkinlik)
final financeOverviewProvider =
    FutureProvider.family<List<FinanceOverviewRow>, ReportDateRange>(
        (ref, range) async {
  return ref
      .watch(financeDataSourceProvider)
      .getFinanceOverview(from: range.from, to: range.to);
});

/// Etkinlik finans verisi değiştiğinde ilgili cache'leri temizler.
void invalidateEventFinanceCaches(WidgetRef ref, String eventId) {
  ref.invalidate(eventFinanceDetailProvider(eventId));
  ref.invalidate(eventFinanceSettingsProvider(eventId));
  ref.invalidate(eventFinanceOverviewProvider);
  ref.invalidate(financeOverviewProvider);
  ref.invalidate(eventByIdProvider(eventId));
  ref.invalidate(eventParticipantsProvider(eventId));
  ref.invalidate(upcomingEventsProvider);
  ref.invalidate(allEventsProvider);
}
