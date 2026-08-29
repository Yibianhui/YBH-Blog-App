import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';
import 'blog_host.dart';
import 'data/wp_auth.dart';

class YbhApp extends StatefulWidget {
  const YbhApp({super.key});

  @override
  State<YbhApp> createState() => _YbhAppState();
}

class _YbhAppState extends State<YbhApp> {
  static const String _darkModeKey = 'ybh_dark_mode';

  bool _darkMode = false;

  @override
  void initState() {
    super.initState();
    _loadDarkMode();
    wpAuth.load();
  }

  Future<void> _loadDarkMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() => _darkMode = prefs.getBool(_darkModeKey) ?? false);
    } catch (_) {
      // 读取失败则保持默认。
    }
  }

  Future<void> _toggleDarkMode(bool value) async {
    setState(() => _darkMode = value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_darkModeKey, value);
    } catch (_) {
      // 忽略写入失败。
    }
  }

  @override
  Widget build(BuildContext context) {
    const primary = Color(AppConfig.themeColorValue);
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      themeMode: _darkMode ? ThemeMode.dark : ThemeMode.system,
      theme: _buildTheme(primary, dark: false),
      darkTheme: _buildTheme(primary, dark: true),
      home: BlogHost(
        darkMode: _darkMode,
        onToggleDarkMode: _toggleDarkMode,
      ),
    );
  }

  ThemeData _buildTheme(Color primary, {required bool dark}) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: dark ? Brightness.dark : Brightness.light,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      primaryColor: primary,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        linearTrackColor: colorScheme.primary.withValues(alpha: 0.2),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12)),
      ),
    );
  }
}
