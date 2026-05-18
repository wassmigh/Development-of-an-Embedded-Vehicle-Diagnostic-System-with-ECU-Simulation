import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'utils/app_theme.dart';
import 'services/firebase_service.dart';
import 'screens/dashboard_screen.dart';
import 'screens/live_data_screen.dart';
import 'screens/vehicle_health_screen.dart';
import 'screens/history_screen.dart';
import 'package:firebase_database/firebase_database.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseDatabase.instance.databaseURL =
      "https://smartcardiag-default-rtdb.europe-west1.firebasedatabase.app";

  // Seed static data once if it doesn't exist.
  // The Raspberry Pi will update liveData — the app just listens.
  await FirebaseService.seedDemoData();

  runApp(const SmartCarDiagApp());
}

class SmartCarDiagApp extends StatelessWidget {
  const SmartCarDiagApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartCarDiag',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const MainNavigation(),
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});
  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _index = 0;

  final _screens = const [
    DashboardScreen(),
    LiveDataScreen(),
    VehicleHealthScreen(),
    HistoryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_index],
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: AppColors.cardBorder, width: 1),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _index,
          onTap: (i) => setState(() => _index = i),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.grid_view_rounded),
              label: 'DASHBOARD',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart_rounded),
              label: 'LIVE',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.monitor_heart_outlined),
              label: 'HEALTH',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.history_rounded),
              label: 'HISTORY',
            ),
          ],
        ),
      ),
    );
  }
}
