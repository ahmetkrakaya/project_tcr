import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/strava_connection_report_model.dart';
import 'strava_provider.dart';

final stravaConnectionReportProvider =
    FutureProvider<StravaConnectionReportModel>((ref) async {
  final dataSource = ref.watch(stravaRemoteDataSourceProvider);
  return dataSource.getStravaConnectionReport();
});
