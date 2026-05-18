import 'package:firebase_database/firebase_database.dart';

class FirebaseService {
  static final FirebaseDatabase _db = FirebaseDatabase.instance;

  // ── Points to your real data path in Firebase ──
  static const String _vehiclePath = 'users/user_12345/vehicles/vehicle_001';

  // ── Refs ──
  static DatabaseReference get liveDataRef => _db.ref('$_vehiclePath/liveData');
  static DatabaseReference get healthRef => _db.ref('$_vehiclePath/health');
  static DatabaseReference get historyRef => _db.ref('$_vehiclePath/history');
  static DatabaseReference get alertsRef => _db.ref('$_vehiclePath/alerts');

  /// Seeds static data only if nodes don't exist yet.
  /// The Raspberry Pi will write to liveData in real time —
  /// every StreamBuilder in the app will update automatically.
  static Future<void> seedDemoData() async {
    // ── liveData ──
    final liveSnap = await liveDataRef.get();
    if (!liveSnap.exists) {
      await liveDataRef.set({
        'rpm': 3200,
        'speed': 68,
        'temp': 92,
        'fuelLevel': 64,
        'engineLoad': 24,
        'batteryVoltage': 14.2,
        'batteryStatus': 'OPTIMAL',
        'avgConsumption': 7.4,
        'isStreaming': true,
        'timestamp': ServerValue.timestamp,
      });
    } else {
      // Migrate old nested battery shape if present
      final data = (liveSnap.value as Map?) ?? {};
      if (data['battery'] != null && data['batteryVoltage'] == null) {
        final batt = data['battery'] as Map;
        await liveDataRef.update({
          'batteryVoltage': batt['voltage'] ?? 14.2,
          'batteryStatus': batt['status'] ?? 'OPTIMAL',
          'battery': null,
        });
      }
    }

    // ── alerts ──
    final alertsSnap = await alertsRef.get();
    if (!alertsSnap.exists) {
      await alertsRef.set({
        'alert_1': {
          'type': 'DTC',
          'code': 'P0301',
          'message': 'DTC Detected: P0301',
          'active': true,
        },
      });
    }

    // ── health ──
    final healthSnap = await healthRef.get();
    if (!healthSnap.exists) {
      await healthRef.set({
        'overallScore': 85,
        'statusMessage': 'Systems check complete',
        'tempTrend': [60, 70, 55, 80, 65],
        'loadTrend': [40, 55, 70, 50, 65, 80, 90],
        'detectedIssues': {
          'issue_1': {
            'title': 'High engine load',
            'description': 'Detected at 3,200 RPM consistently',
            'iconType': 'speed',
          },
          'issue_2': {
            'title': 'Abnormal temp pattern',
            'description': 'Coolant fluctuating +/- 5°C from norm',
            'iconType': 'temp',
          },
        },
        'activeDTCs': {
          'P0300': {
            'description': 'Random/Multiple Cylinder Misfire Detected',
            'severity': 'ORANGE',
          },
          'P0171': {
            'description': 'System Too Lean (Bank 1)',
            'severity': 'YELLOW',
          },
        },
        'mlForecast':
            'Predictive maintenance suggests checking spark plugs within the next 500 km to prevent potential escalation of P0300 misfire events.',
      });
    }

    // ── history ──
    final historySnap = await historyRef.get();
    if (!historySnap.exists) {
      await historyRef.set({
        'summary': {
          'day': {
            'engineSpeed': {'avg': 1800, 'peak': 5200},
            'coolantTemp': {'avg': 88, 'max': 98},
            'engineLoad': {'avg': 38, 'rating': 'GOOD'},
          },
          'week': {
            'engineSpeed': {'avg': 2400, 'peak': 6640},
            'coolantTemp': {'avg': 92, 'max': 104},
            'engineLoad': {'avg': 42, 'rating': 'OPTIMAL'},
          },
          'month': {
            'engineSpeed': {'avg': 2100, 'peak': 7200},
            'coolantTemp': {'avg': 90, 'max': 106},
            'engineLoad': {'avg': 40, 'rating': 'OPTIMAL'},
          },
        },
        'performanceTimeline': {
          'mon': {'load': 30, 'efficiency': 75},
          'tue': {'load': 45, 'efficiency': 80},
          'wed': {'load': 55, 'efficiency': 70},
          'thu': {'load': 40, 'efficiency': 85},
          'fri': {'load': 65, 'efficiency': 60},
          'sat': {'load': 70, 'efficiency': 55},
          'sun': {'load': 35, 'efficiency': 90},
        },
        'mlAnomalies': {
          'anomaly_1': {
            'title': 'Cylinder 3 Misfire Detected',
            'dateString': 'AUG 24, 14:20',
            'subtitle': 'P0303 CODE',
            'severity': 'Critical',
            'iconType': 'alert',
          },
          'anomaly_2': {
            'title': 'Oxygen Sensor (O2S) Latency',
            'dateString': 'AUG 22, 00:12',
            'subtitle': 'TRANSIENT PEAK',
            'severity': 'Moderate',
            'iconType': 'sensor',
          },
          'anomaly_3': {
            'title': 'Coolant Temperature Drift',
            'dateString': 'AUG 16, 13:45',
            'subtitle': 'ENVIRONMENTAL OFFSET',
            'severity': 'Low',
            'iconType': 'temp',
          },
        },
      });
    }
  }
}
