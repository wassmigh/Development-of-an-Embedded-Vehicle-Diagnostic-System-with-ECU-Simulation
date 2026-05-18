import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:fl_chart/fl_chart.dart';
import '../utils/app_theme.dart';
import '../services/firebase_service.dart';
import '../widgets/custom_app_bar.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _filter = 'week';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(
              Icons.settings,
              color: AppColors.textSecondary,
              size: 24,
            ),
          ),
        ],
      ),
      backgroundColor: AppColors.scaffold,
      body: SafeArea(
        child: StreamBuilder<DatabaseEvent>(
          stream: FirebaseService.historyRef.onValue,
          builder: (ctx, snap) {
            final d = (snap.data?.snapshot.value as Map?) ?? {};
            final summaryAll = (d['summary'] as Map?) ?? {};
            final filterMap = (summaryAll[_filter] as Map?) ?? {};
            // Pick the latest date entry from the filter map
            final sortedDates = filterMap.keys.toList()
              ..sort((a, b) => a.toString().compareTo(b.toString()));
            final latestDate = sortedDates.isNotEmpty ? sortedDates.last : null;
            final summary = latestDate != null
                ? (filterMap[latestDate] as Map?) ?? {}
                : <String, dynamic>{};
            final es = (summary['engineSpeed'] as Map?) ?? {};
            final ct = (summary['coolantTemp'] as Map?) ?? {};
            final el = (summary['engineLoad'] as Map?) ?? {};
            final timeline = (d['performanceTimeline'] as Map?) ?? {};
            final anomalies = (d['mlAnomalies'] as Map?) ?? {};

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // _appBar(),
                  const SizedBox(height: 16),
                  const Text(
                    'Data History',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Review long-term vehicle performance trends.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _filterTabs(),
                  const SizedBox(height: 16),
                  _statCard(
                    'ENGINE SPEED (RPM)',
                    Icons.speed,
                    _fmtAvg(es['avg']),
                    'AVG',
                    'PEAK REACHED',
                    '${_fmtPeak(es['peak'])} RPM',
                  ),
                  const SizedBox(height: 12),
                  _statCard(
                    'COOLANT TEMP',
                    Icons.thermostat_outlined,
                    '${ct['avg'] ?? 0}°',
                    'AVG',
                    'MAX RECORDED',
                    '${ct['max'] ?? 0}°C',
                  ),
                  const SizedBox(height: 12),
                  _statCard(
                    'ENGINE LOAD',
                    Icons.show_chart,
                    '${el['avg'] ?? 0}%',
                    'AVG',
                    'EFFICIENCY RATING',
                    el['rating']?.toString() ?? 'N/A',
                  ),
                  const SizedBox(height: 20),
                  _timelineSection(timeline),
                  const SizedBox(height: 20),
                  _anomalySection(anomalies),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  String _fmtAvg(dynamic v) {
    final n =
        v is num
            ? v.toInt()
            : (num.tryParse(v?.toString() ?? '')?.toInt() ?? 0);
    return n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';
  }

  String _fmtPeak(dynamic v) {
    final n =
        v is num
            ? v.toInt()
            : (num.tryParse(v?.toString() ?? '')?.toInt() ?? 0);
    return n >= 1000
        ? '${n ~/ 1000},${(n % 1000).toString().padLeft(3, '0')}'
        : '$n';
  }


  Widget _filterTabs() => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.cardBorder),
    ),
    child: Row(
      children:
          ['day', 'week', 'month'].map((f) {
            final sel = f == _filter;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _filter = f),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color:
                        sel
                            ? AppColors.cyan.withValues(alpha: .15)
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      f[0].toUpperCase() + f.substring(1),
                      style: TextStyle(
                        color: sel ? AppColors.cyan : AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
    ),
  );

  Widget _statCard(
    String title,
    IconData ic,
    String big,
    String bigLabel,
    String subLabel,
    String subVal,
  ) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.cardBorder),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .8,
                ),
              ),
            ),
            Icon(ic, color: AppColors.cyan, size: 18),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              big,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 40,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.cyan.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  bigLabel,
                  style: const TextStyle(
                    color: AppColors.cyan,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              subLabel,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                letterSpacing: .5,
              ),
            ),
            Text(
              subVal,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _timelineSection(Map timeline) {
    // Sort date keys chronologically and take up to last 7 entries
    final sortedKeys = timeline.keys.toList()
      ..sort((a, b) => a.toString().compareTo(b.toString()));
    final recentKeys = sortedKeys.length > 7
        ? sortedKeys.sublist(sortedKeys.length - 7)
        : sortedKeys;
    // Build short labels from date keys (e.g. "2026-05-07" -> "05/07")
    final labels = recentKeys.map((k) {
      final parts = k.toString().split('-');
      return parts.length >= 3 ? '${parts[1]}/${parts[2]}' : k.toString();
    }).toList();
    final loadVals =
        recentKeys
            .map((k) => ((timeline[k] as Map?)?['loadPercent'] ?? 0).toDouble())
            .toList();
    final effVals =
        recentKeys
            .map((k) => ((timeline[k] as Map?)?['efficiency'] ?? 0).toDouble())
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Performance\nTimeline',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'TELEMETRY DATA\nDISTRIBUTION',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                      letterSpacing: .5,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: AppColors.cyan,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'LOAD',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: AppColors.cyanDark,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'EFFICIENCY',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 140,
          child: BarChart(
            BarChartData(
              gridData: const FlGridData(show: false),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    getTitlesWidget: (v, _) {
                      final idx = v.toInt();
                      if (idx < 0 || idx >= labels.length)
                        return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          labels[idx],
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 9,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              barGroups: List.generate(
                recentKeys.length,
                (i) => BarChartGroupData(
                  x: i,
                  barsSpace: 2,
                  barRods: [
                    BarChartRodData(
                      toY: loadVals[i],
                      width: 12,
                      color: AppColors.cyan,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(3),
                      ),
                    ),
                    BarChartRodData(
                      toY: effVals[i],
                      width: 12,
                      color: AppColors.cyanDark,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(3),
                      ),
                    ),
                  ],
                ),
              ),
              maxY: 100,
            ),
          ),
        ),
      ],
    );
  }

  Widget _anomalySection(Map anomalies) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.bar_chart, color: AppColors.textPrimary, size: 20),
            const SizedBox(width: 8),
            const Text(
              'ML Anomalies',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${anomalies.length} DETECTED',
                style: const TextStyle(
                  color: AppColors.error,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...anomalies.values.map((v) {
          final m = v as Map;
          final sev = m['severity'] ?? '';
          Color sevColor;
          if (sev == 'Critical') {
            sevColor = AppColors.error;
          } else if (sev == 'Moderate') {
            sevColor = AppColors.warningOrange;
          } else {
            sevColor = AppColors.warningYellow;
          }

          IconData sevIcon;
          if (m['iconType'] == 'alert') {
            sevIcon = Icons.warning_rounded;
          } else if (m['iconType'] == 'sensor') {
            sevIcon = Icons.sensors;
          } else {
            sevIcon = Icons.thermostat;
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: sevColor.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(sevIcon, color: sevColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m['title'] ?? '',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${m['dateString'] ?? ''}  •  ${m['subtitle'] ?? ''}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    sev.toString(),
                    style: TextStyle(
                      color: sevColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: () {},
            child: const Text(
              'VIEW FULL DIAGNOSTIC LOG',
              style: TextStyle(
                color: AppColors.cyan,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: .8,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
