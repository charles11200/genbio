import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const GenBioReviewApp());
}

class GenBioReviewApp extends StatelessWidget {
  const GenBioReviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gen Bio Offline Review',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.green,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}