import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import '../utils/app_theme.dart';
import '../services/firebase_service.dart';
import '../widgets/custom_app_bar.dart';

class VehicleHealthScreen extends StatelessWidget {
  const VehicleHealthScreen({super.key});

  /// Firebase stores JSON arrays as Maps with integer string keys ("0", "1", …).
  /// This helper converts either a real List or such a Map back to List<double>.
  static List<double> _toDoubleList(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) {
      return raw.map((e) => (e as num).toDouble()).toList();
    }
    if (raw is Map) {
      // Keys are "0", "1", "2", … — sort numerically then extract values.
      final sorted =
          raw.entries.toList()..sort(
            (a, b) => (int.tryParse(a.key.toString()) ?? 0).compareTo(
              int.tryParse(b.key.toString()) ?? 0,
            ),
          );
      return sorted.map((e) => (e.value as num).toDouble()).toList();
    }
    return [];
  }

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
          stream: FirebaseService.healthRef.onValue,
          builder: (ctx, snap) {
            final d = (snap.data?.snapshot.value as Map?) ?? {};
            final score = (d['overallScore'] ?? 0).toInt();
            final issuesMap = (d['detectedIssues'] as Map?) ?? {};
            final dtcMap = (d['activeDTCs'] as Map?) ?? {};
            final forecast = d['mlForecast'] ?? '';

            // Fix: Firebase can return arrays as Maps with "0","1",… keys
            final tempTrend = _toDoubleList(d['tempTrend']);
            final loadTrend = _toDoubleList(d['loadTrend']);

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // _appBar(),
                  const SizedBox(height: 16),
                  _scoreCard(score, tempTrend, loadTrend),
                  const SizedBox(height: 20),
                  _sectionTitle(Icons.search, 'DETECTED ISSUES / ANOMALIES'),
                  const SizedBox(height: 10),
                  ...issuesMap.values.map((v) {
                    final m = v as Map;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _issueCard(
                        m['title'] ?? '',
                        m['description'] ?? '',
                        m['iconType'] ?? 'speed',
                      ),
                    );
                  }),
                  const SizedBox(height: 16),
                  _dtcSection(dtcMap),
                  const SizedBox(height: 16),
                  _forecastCard(forecast.toString()),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        ),
      ),
    );
  }


  // ── Health Score Card ──
  Widget _scoreCard(int score, List<double> tempT, List<double> loadT) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'DIAGNOSTIC STATUS',
            style: TextStyle(
              color: AppColors.cyan,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Overall Vehicle\nHealth Score',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'AI-driven analysis based on real-time\nsensor data and telemetric history.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: SizedBox(
              height: 160,
              width: 160,
              child: SfRadialGauge(
                axes: [
                  RadialAxis(
                    minimum: 0,
                    maximum: 100,
                    startAngle: 135,
                    endAngle: 45,
                    showLabels: false,
                    showTicks: false,
                    axisLineStyle: const AxisLineStyle(
                      thickness: 12,
                      color: AppColors.gaugeTrack,
                      cornerStyle: CornerStyle.bothCurve,
                    ),
                    pointers: [
                      RangePointer(
                        value: score.toDouble(),
                        width: 12,
                        color: AppColors.cyan,
                        cornerStyle: CornerStyle.bothCurve,
                        enableAnimation: true,
                        animationDuration: 1500,
                      ),
                    ],
                    annotations: [
                      GaugeAnnotation(
                        widget: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$score',
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 48,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const Text(
                              '/ 100',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        positionFactor: 0,
                        angle: 90,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _miniTrend('ENGINE TEMP TREND', tempT)),
              const SizedBox(width: 16),
              Expanded(child: _miniTrend('ENGINE LOAD TREND', loadT)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniTrend(String label, List<double> data) {
    if (data.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: .5,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '—',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      );
    }
    final maxV = data
        .reduce((a, b) => a > b ? a : b)
        .clamp(1.0, double.infinity);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 9,
            fontWeight: FontWeight.w600,
            letterSpacing: .5,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children:
              data
                  .map(
                    (v) => Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        height: 24 * (v / maxV).clamp(0.2, 1.0),
                        decoration: BoxDecoration(
                          color: AppColors.cyan,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  )
                  .toList(),
        ),
      ],
    );
  }

  Widget _sectionTitle(IconData ic, String t) => Row(
    children: [
      Icon(ic, color: AppColors.textSecondary, size: 18),
      const SizedBox(width: 8),
      Text(
        t,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: .8,
        ),
      ),
    ],
  );

  // ── Issue Card ──
  Widget _issueCard(String title, String desc, String iconType) {
    final ic = iconType == 'temp' ? Icons.ac_unit : Icons.speed;
    final cl = iconType == 'temp' ? AppColors.cyan : AppColors.error;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cl.withValues(alpha: .15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(ic, color: cl, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── DTC Section ──
  Widget _dtcSection(Map dtcMap) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.info_outline,
              color: AppColors.textSecondary,
              size: 18,
            ),
            const SizedBox(width: 8),
            const Text(
              'ACTIVE DTC CODES',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: .8,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${dtcMap.length} FAULTS DETECTED',
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
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: const [
                    SizedBox(
                      width: 60,
                      child: Text(
                        'CODE',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: .5,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'DESCRIPTION',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: .5,
                        ),
                      ),
                    ),
                    Text(
                      'SEVERITY',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .5,
                      ),
                    ),
                  ],
                ),
              ),
              ...dtcMap.entries.map((e) {
                final code = e.key.toString();
                final info = e.value as Map;
                final sev = info['severity'] ?? 'ORANGE';
                final sevColor =
                    sev == 'YELLOW'
                        ? AppColors.warningYellow
                        : AppColors.warningOrange;
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 60,
                        child: Text(
                          code,
                          style: const TextStyle(
                            color: AppColors.cyan,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          info['description'] ?? '',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: sevColor.withValues(alpha: .15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          sev.toString(),
                          style: TextStyle(
                            color: sevColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }

  // ── ML Forecast Card ──
  Widget _forecastCard(String text) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppColors.cardHighlight,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.cardBorder),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.bar_chart, color: AppColors.cyan, size: 20),
            SizedBox(width: 8),
            Text(
              'ML System Forecast',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          text,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () {},
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.cyan,
            foregroundColor: AppColors.scaffold,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          child: const Text(
            'SCHEDULE SERVICE',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: .5,
            ),
          ),
        ),
      ],
    ),
  );
}
