import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/event_remote_datasource.dart';
import '../../data/models/engagement_excuse_model.dart';
import 'event_provider.dart';

final pendingEngagementExcuseProvider =
    FutureProvider<PendingEngagementExcuseModel?>((ref) async {
  final dataSource = ref.watch(eventDataSourceProvider);
  return dataSource.getPendingEngagementExcuse();
});

final engagementExcuseAdminReportsProvider =
    FutureProvider<EngagementExcuseAdminReportsModel>((ref) async {
  final dataSource = ref.watch(eventDataSourceProvider);
  return dataSource.getEngagementExcuseAdminReports();
});

final engagementExcuseActionsProvider = Provider<EngagementExcuseActions>((ref) {
  final dataSource = ref.watch(eventDataSourceProvider);
  return EngagementExcuseActions(ref, dataSource);
});

class EngagementExcuseActions {
  final Ref _ref;
  final EventRemoteDataSource _dataSource;

  EngagementExcuseActions(this._ref, this._dataSource);

  Future<SendEngagementExcuseResultModel> sendRequests({
    required List<String> userIds,
    required String excuseType,
  }) async {
    final result = await _dataSource.sendEngagementExcuseRequests(
      userIds: userIds,
      excuseType: excuseType,
    );
    _ref.invalidate(engagementExcuseAdminReportsProvider);
    return result;
  }

  Future<void> submitExcuse({
    required String requestId,
    required String text,
  }) async {
    await _dataSource.submitEngagementExcuse(
      requestId: requestId,
      text: text,
    );
    _ref.invalidate(pendingEngagementExcuseProvider);
    _ref.invalidate(engagementExcuseAdminReportsProvider);
  }

  Future<void> acceptExcuse({
    required String requestId,
    DateTime? exemptUntil,
  }) async {
    await _dataSource.reviewEngagementExcuse(
      requestId: requestId,
      action: 'accept',
      exemptUntil: exemptUntil,
    );
    _ref.invalidate(engagementExcuseAdminReportsProvider);
    _ref.invalidate(userEngagementReportsProvider);
  }

  Future<void> banFromExcuse({required String requestId}) async {
    await _dataSource.reviewEngagementExcuse(
      requestId: requestId,
      action: 'ban',
    );
    _ref.invalidate(engagementExcuseAdminReportsProvider);
    _ref.invalidate(userEngagementReportsProvider);
  }

  void refreshPending() {
    _ref.invalidate(pendingEngagementExcuseProvider);
  }
}
