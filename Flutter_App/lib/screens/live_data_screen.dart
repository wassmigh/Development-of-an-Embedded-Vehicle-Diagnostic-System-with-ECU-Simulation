import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:fl_chart/fl_chart.dart';
import '../utils/app_theme.dart';
import '../services/firebase_service.dart';
import '../widgets/custom_app_bar.dart';

class LiveDataScreen extends StatefulWidget {
  const LiveDataScreen({super.key});
  @override
  State<LiveDataScreen> createState() => _LiveDataScreenState();
}

class _LiveDataScreenState extends State<LiveDataScreen> {
  final List<double> _rpmHist = [];
  final List<double> _speedHist = [];
  final List<double> _tempHist = [];

  // Latest values from Firebase — kept in state so the UI always has them
  int _rpm = 0;
  int _spd = 0;
  int _tmp = 0;
  int _eLoad = 0;
  double _bV = 0;
  String _bS = 'N/A';
  bool _streaming = false;

  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = FirebaseService.liveDataRef.onValue.listen((event) {
      final d = (event.snapshot.value as Map?) ?? {};
      if (!mounted) return;
      setState(() {
        // Safe parser: handles both num and String values from Firebase
        double _n(dynamic v) =>
            (v is num)
                ? v.toDouble()
                : double.tryParse(v?.toString() ?? '') ?? 0.0;

        _rpm = _n(d['rpm']).toInt();
        _spd = _n(d['speed']).toInt();
        _tmp = _n(d['temp']).toInt();
        _eLoad = _n(d['engineLoad']).toInt();
        _bV = _n(d['battery']['voltage']);
        _bS = (d['battery']['status'] ?? 'N/A').toString();
        _streaming = d['isStreaming'] ?? false;

        _add(_rpmHist, _rpm.toDouble());
        _add(_speedHist, _spd.toDouble());
        _add(_tempHist, _tmp.toDouble());
      });
    });
  }

  void _add(List<double> l, double v) {
    l.add(v);
    if (l.length > 20) l.removeAt(0);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String _fmt(int n) =>
      n >= 1000
          ? '${n ~/ 1000},${(n % 1000).toString().padLeft(3, '0')}'
          : '$n';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'LIVE DATA',
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(
              Icons.refresh,
              color: AppColors.textSecondary,
              size: 22,
            ),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(
              Icons.settings,
              color: AppColors.textSecondary,
              size: 22,
            ),
          ),
        ],
      ),
      backgroundColor: AppColors.scaffold,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              // _appBar(),
              const SizedBox(height: 16),
              _streamBadge(_streaming),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: _loadCard(_eLoad)),
                  const SizedBox(width: 12),
                  Expanded(child: _battCard(_bV, _bS)),
                ],
              ),
              const SizedBox(height: 16),
              _chartCard(
                Icons.speed,
                'ENGINE RPM',
                '${_fmt(_rpm)} RPM',
                _rpmHist,
                8000,
              ),
              const SizedBox(height: 14),
              _chartCard(
                Icons.trending_up,
                'VEHICLE SPEED',
                '$_spd MPH',
                _speedHist,
                200,
              ),
              const SizedBox(height: 14),
              _chartCard(
                Icons.thermostat,
                'ENGINE TEMP',
                '$_tmp° F',
                _tempHist,
                250,
              ),
              // const SizedBox(height: 16),
              // _streamBadge(_streaming),
              // const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }


  Widget _loadCard(int v) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.cardBorder),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ENGINE LOAD',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: .8,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '$v',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 36,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text(
                '%',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: (v / 100).clamp(0.0, 1.0),
            minHeight: 4,
            backgroundColor: AppColors.gaugeTrack,
            valueColor: const AlwaysStoppedAnimation(AppColors.cyan),
          ),
        ),
      ],
    ),
  );

  Widget _battCard(double v, String s) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.cardBorder),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'BATTERY',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: .8,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              v.toStringAsFixed(1),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 36,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text(
                'V',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Icon(Icons.bolt, color: AppColors.cyan, size: 14),
            const SizedBox(width: 4),
            Text(
              s,
              style: const TextStyle(
                color: AppColors.cyan,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _chartCard(
    IconData ic,
    String lbl,
    String val,
    List<double> pts,
    double maxY,
  ) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.cyan.withValues(alpha: .2)),
    ),
    child: Column(
      children: [
        Row(
          children: [
            Icon(ic, color: AppColors.cyan, size: 18),
            const SizedBox(width: 8),
            Text(
              lbl,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: .8,
              ),
            ),
            const Spacer(),
            Text(
              val,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 100,
          child:
              pts.length < 2
                  ? const Center(
                    child: Text(
                      'Waiting for data...',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  )
                  : LineChart(
                    LineChartData(
                      gridData: const FlGridData(show: false),
                      titlesData: const FlTitlesData(show: false),
                      borderData: FlBorderData(show: false),
                      minX: 0,
                      maxX: (pts.length - 1).toDouble(),
                      minY: 0,
                      maxY: maxY,
                      lineBarsData: [
                        LineChartBarData(
                          spots:
                              pts
                                  .asMap()
                                  .entries
                                  .map((e) => FlSpot(e.key.toDouble(), e.value))
                                  .toList(),
                          isCurved: true,
                          color: AppColors.cyan,
                          barWidth: 2.5,
                          isStrokeCapRound: true,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                AppColors.cyan.withValues(alpha: .25),
                                AppColors.cyan.withValues(alpha: 0),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    duration: const Duration(milliseconds: 1000),
                    curve: Curves.easeInOutCubic,
                  ),
        ),
      ],
    ),
  );

  Widget _streamBadge(bool on) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: AppColors.cyan.withValues(alpha: .4)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: on ? AppColors.success : AppColors.error,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        const Text(
          'OBDII REAL-TIME STREAMING',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
      ],
    ),
  );
}
