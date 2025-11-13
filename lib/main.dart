import 'package:flutter/material.dart';
import 'screens/stove_detector_screen.dart';

void main() {
  runApp(const StoveDetectorApp());
}

class StoveDetectorApp extends StatelessWidget {
  const StoveDetectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stove Detector',
      theme: ThemeData(
        primarySwatch: Colors.orange,
        useMaterial3: true,
      ),
      home: const StoveDetectorScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
