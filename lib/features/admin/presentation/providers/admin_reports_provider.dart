import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/datasources/admin_reports_remote_datasource.dart';
import '../../data/models/admin_reports_models.dart';

final _adminReportsDataSourceProvider =
    Provider<AdminReportsRemoteDataSource>((ref) {
  return AdminReportsRemoteDataSource(Supabase.instance.client);
});

/// Etkinlik turu trendi (varsayilan son 6 ay).
final eventTypeTrendProvider = FutureProvider.family<List<EventTypeTrendItem>,
    ({DateTime start, DateTime end})>((ref, range) async {
  final ds = ref.watch(_adminReportsDataSourceProvider);
  return ds.getEventTypeTrend(start: range.start, end: range.end);
});

/// Grup durum panosu.
final groupStatusOverviewProvider =
    FutureProvider<List<GroupStatusItem>>((ref) async {
  final ds = ref.watch(_adminReportsDataSourceProvider);
  return ds.getGroupStatusOverview();
});

/// Kisi 360 birlesik ozet.
final person360Provider =
    FutureProvider.family<Person360, String>((ref, userId) async {
  final ds = ref.watch(_adminReportsDataSourceProvider);
  return ds.getPerson360(userId);
});
