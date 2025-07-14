// lib/main.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'fan_home_page.dart';
import 'ad_helper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(
    [DeviceOrientation.portraitUp],
  );
  await AdHelper.initializeAds();

  final prefs  = await SharedPreferences.getInstance();
  final stored = prefs.getString('themeMode');
  final initialTheme = stored == 'light'
      ? ThemeMode.light
      : stored == 'dark'
          ? ThemeMode.dark
          : ThemeMode.system;

  runApp(MyApp(initialTheme));
}

class MyApp extends StatefulWidget {
  final ThemeMode initialTheme;
  const MyApp(this.initialTheme, {Key? key}) : super(key: key);
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late ThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    _themeMode = widget.initialTheme;
  }

  Future<void> _persistTheme(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeMode', mode.toString().split('.').last);
  }

  void _updateTheme(ThemeMode mode) {
    setState(() => _themeMode = mode);
    _persistTheme(mode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Click Miner',
      theme: ThemeData.light().copyWith(
        scaffoldBackgroundColor: Colors.grey[600],
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.grey[300],
          iconTheme: IconThemeData(color: Colors.black),
        ),
      ),
      darkTheme: ThemeData.dark(),
      themeMode: _themeMode,
      home: FanHomePage(
        currentTheme: _themeMode,
        onThemeChanged: _updateTheme,
      ),
    );
  }
}
