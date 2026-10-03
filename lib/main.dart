import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'services/sound_service.dart';

void main() {
  runApp(const GenBioReviewApp());
}

class GenBioReviewApp extends StatefulWidget {
  const GenBioReviewApp({super.key});

  @override
  State<GenBioReviewApp> createState() => _GenBioReviewAppState();
}

class _GenBioReviewAppState extends State<GenBioReviewApp> {
  @override
  void initState() {
    super.initState();
    // Started once, here, for the app's whole lifetime - not per-screen.
    // SoundService's player just keeps looping underneath every screen
    // (home, import, every game mode) regardless of Navigator push/pop,
    // since it isn't tied to any one screen's widget tree.
    SoundService.startBackgroundMusic();
  }

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