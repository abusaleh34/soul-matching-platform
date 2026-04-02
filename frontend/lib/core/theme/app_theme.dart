import 'package:flutter/material.dart';

class AppTheme {
  // Brand Colors
  static const Color primaryOliveGreen = Color(0xFF4A5D23); // Deep Olive Green
  static const Color primaryNavyBlue = Color(0xFF1A2A3A); // Navy Blue
  static const Color backgroundBeige = Color(0xFFE6D5B8); // Sand Beige
  static const Color backgroundIvory = Color(0xFFFFFFF0); // Ivory White

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: backgroundIvory,
      colorScheme: const ColorScheme.light(
        primary: primaryOliveGreen,
        secondary: primaryNavyBlue,
        background: backgroundIvory,
        surface: Colors.white,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onBackground: primaryNavyBlue,
      ),
      fontFamily: 'Tajawal', // Suggested premium Arabic font
      textTheme: const TextTheme(
        headlineLarge: TextStyle(color: primaryNavyBlue, fontWeight: FontWeight.bold, fontSize: 32),
        headlineMedium: TextStyle(color: primaryNavyBlue, fontWeight: FontWeight.w700, fontSize: 24),
        bodyLarge: TextStyle(color: primaryNavyBlue, fontSize: 18),
        bodyMedium: TextStyle(color: primaryNavyBlue, fontSize: 16),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryOliveGreen,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
