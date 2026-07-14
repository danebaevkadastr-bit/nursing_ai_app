import 'package:flutter/material.dart';
import 'main_screen.dart';

void main() {
  runApp(const NursingAiApp());
}

class NursingAiApp extends StatelessWidget {
  const NursingAiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nursing AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Inter',
      ),
      home: const MainScreen(),
    );
  }
}
