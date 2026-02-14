import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../widgets/statistics_widget.dart';

/// Statistics Page - Haftalık ve aylık istatistikler
class StatisticsPage extends StatelessWidget {
  final String? userId; // Başka kullanıcının istatistiklerini görmek için
  
  const StatisticsPage({super.key, this.userId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('İstatistikler'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        child: StatisticsWidget(userId: userId),
      ),
    );
  }
}
