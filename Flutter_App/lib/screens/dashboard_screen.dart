import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import 'package:percent_indicator/percent_indicator.dart';
import '../utils/app_theme.dart';
import '../services/firebase_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _alertDismissed = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: _buildAppBar(),
          ),
        ),
      ),
      backgroundColor: AppColors.scaffold,
      body: SafeArea(
        // ── Outer stream: liveData ──
        child: StreamBuilder<DatabaseEvent>(
          stream: FirebaseService.liveDataRef.onValue,
          builder: (context, liveSnap) {
            final liveData = (liveSnap.data?.snapshot.value as Map?) ?? {};

            // Safe parser: handles both num and String values from Firebase
            double _n(dynamic v) =>
                (v is num)
                    ? v.toDouble()
                    : double.tryParse(v?.toString() ?? '') ?? 0.0;

            final rpm = _n(liveData['rpm']);
            final speed = _n(liveData['speed']);
            final temp = _n(liveData['temp']).toInt();
            final fuel = _n(liveData['fuelLevel']).toInt();
            final batteryMap = (liveData['battery'] as Map?) ?? {};
            final batteryV = _n(batteryMap['voltage']);
            final avgConsumption = _n(liveData['avgConsumption']);

            // ── Inner stream: health (for overallScore) ──
            return StreamBuilder<DatabaseEvent>(
              stream: FirebaseService.healthRef.onValue,
              builder: (context, healthSnap) {
                final healthData =
                    (healthSnap.data?.snapshot.value as Map?) ?? {};
                final healthScore = (healthData['overallScore'] ?? 0).toInt();

                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 16),

                      if (!_alertDismissed) _buildAlertBanner(),
                      if (!_alertDismissed) const SizedBox(height: 16),

                      // ── Gauges Row ──
                      Row(
                        children: [
                          Expanded(
                            child: _buildGaugeCard(
                              value: rpm / 1000,
                              max: 8,
                              label: 'RPM x1000',
                              displayText: (rpm / 1000).toStringAsFixed(1),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildGaugeCard(
                              value: speed,
                              max: 220,
                              label: 'KM/H',
                              displayText: speed.toInt().toString(),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // ── Indicators Row ──
                      Row(
                        children: [
                          Expanded(
                            child: _buildIndicatorCard(
                              icon: Icons.thermostat_outlined,
                              label: 'TEMP',
                              value: '$temp°C',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildIndicatorCard(
                              icon: Icons.local_gas_station_outlined,
                              label: 'FUEL',
                              value: '$fuel%',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildIndicatorCard(
                              icon: Icons.bolt,
                              label: 'BATT',
                              value: '${batteryV.toStringAsFixed(1)}V',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // ── Vehicle Health Card ──
                      _buildHealthCard(healthScore),
                      const SizedBox(height: 12),

                      // ── Avg Consumption Card ──
                      _buildConsumptionCard(avgConsumption),
                      const SizedBox(height: 20),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════
  //  APP BAR
  // ══════════════════════════════════════════════
  Widget _buildAppBar() {
    return Row(
      children: [
        const Icon(Icons.directions_car, color: AppColors.cyan, size: 28),
        const SizedBox(width: 10),
        const Text(
          'DIAG SMARTER',
          style: TextStyle(
            color: AppColors.cyan,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
          ),
        ),
        const Spacer(),
        IconButton(
          onPressed: () {},
          icon: const Icon(
            Icons.settings,
            color: AppColors.textSecondary,
            size: 24,
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════
  //  DIAGNOSTIC ALERT BANNER
  // ══════════════════════════════════════════════
  Widget _buildAlertBanner() {
    return StreamBuilder<DatabaseEvent>(
      stream: FirebaseService.alertsRef.onValue,
      builder: (context, snapshot) {
        final alertsMap = (snapshot.data?.snapshot.value as Map?) ?? {};
        if (alertsMap.isEmpty) return const SizedBox.shrink();

        final first = (alertsMap.values.first as Map?) ?? {};
        final message = first['message'] ?? 'Unknown Alert';

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                  color: AppColors.warningOrange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.warning_rounded,
                  color: AppColors.warningOrange,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'DIAGNOSTIC ALERT',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      message.toString(),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _alertDismissed = true),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.textMuted.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close,
                    color: AppColors.textSecondary,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ══════════════════════════════════════════════
  //  RADIAL GAUGE CARD
  // ══════════════════════════════════════════════
  Widget _buildGaugeCard({
    required double value,
    required double max,
    required String label,
    required String displayText,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: SizedBox(
        height: 160,
        child: SfRadialGauge(
          axes: [
            RadialAxis(
              minimum: 0,
              maximum: max,
              startAngle: 135,
              endAngle: 45,
              showLabels: false,
              showTicks: false,
              axisLineStyle: const AxisLineStyle(
                thickness: 10,
                color: AppColors.gaugeTrack,
                cornerStyle: CornerStyle.bothCurve,
              ),
              pointers: <GaugePointer>[
                RangePointer(
                  value: value.clamp(0, max),
                  width: 10,
                  color: AppColors.cyan,
                  cornerStyle: CornerStyle.bothCurve,
                  enableAnimation: true,
                  animationDuration: 2000,
                  gradient: const SweepGradient(
                    colors: [AppColors.cyanDark, AppColors.cyan],
                  ),
                ),
              ],
              annotations: <GaugeAnnotation>[
                GaugeAnnotation(
                  widget: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        displayText,
                        style: const TextStyle(
                          color: AppColors.cyan,
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  positionFactor: 0.0,
                  angle: 90,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════
  //  INDICATOR CARD (Temp, Fuel, Battery)
  // ══════════════════════════════════════════════
  Widget _buildIndicatorCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 22),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════
  //  VEHICLE HEALTH CARD
  // ══════════════════════════════════════════════
  Widget _buildHealthCard(int score) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cyan.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Vehicle Health',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Systems check complete',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '$score',
                style: const TextStyle(
                  color: AppColors.cyan,
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'OPTIMAL',
                style: TextStyle(
                  color: AppColors.success,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: LinearPercentIndicator(
                  animation: true,
                  animationDuration: 1000,
                  lineHeight: 6,
                  percent: (score / 100).clamp(0.0, 1.0),
                  backgroundColor: AppColors.gaugeTrack,
                  linearGradient: const LinearGradient(
                    colors: [AppColors.cyanDark, AppColors.cyan],
                  ),
                  barRadius: const Radius.circular(4),
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════
  //  AVG CONSUMPTION CARD
  // ══════════════════════════════════════════════
  Widget _buildConsumptionCard(double value) {
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
              color: AppColors.cyan.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.speed, color: AppColors.cyan, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AVG CONSUMPTION',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${value.toStringAsFixed(1)} L/100km',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right,
            color: AppColors.textSecondary,
            size: 24,
          ),
        ],
      ),
    );
  }
}
