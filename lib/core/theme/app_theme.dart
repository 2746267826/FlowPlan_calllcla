// 应用主题：双主题（亮色/暗色），紫罗兰主色调
import 'package:flutter/material.dart';

/// FlowPlan 设计令牌
class AppColors {
  // === 主色调（紫罗兰）===
  static const Color primary = Color(0xFF6B5EE4);
  static const Color primaryDark = Color(0xFF7C6DFA);
  static const Color primaryContainer = Color(0xFFE8E5FF);
  static const Color primaryContainerDark = Color(0xFF2D2660);

  // === 亮色主题背景 ===
  static const Color bgLight = Color(0xFFF5F5F7);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceVariantLight = Color(0xFFF0F0F5);

  // === 暗色主题背景 ===
  static const Color bgDark = Color(0xFF0F0F14);
  static const Color surfaceDark = Color(0xFF1A1A24);
  static const Color surfaceVariantDark = Color(0xFF222233);

  // === 语义色 ===
  static const Color error = Color(0xFFE53935);
  static const Color success = Color(0xFF43A047);
  static const Color warning = Color(0xFFFFA726);
  static const Color timeIndicator = Color(0xFFE53935); // 当前时间红线

  // === 任务颜色调色板（日程色块专用，鲜明）===
  static const List<Color> taskPalette = [
    Color(0xFF0EA8A0), // 青绿
    Color(0xFF6B5EE4), // 紫罗兰
    Color(0xFFF5935A), // 橙色
    Color(0xFFE05A7A), // 珊瑚红
    Color(0xFF5AB8E0), // 天蓝
    Color(0xFF8BC34A), // 草绿
    Color(0xFFAB47BC), // 紫色
    Color(0xFFFF7043), // 深橙
    Color(0xFF26A69A), // 蓝绿
    Color(0xFFEC407A), // 粉红
  ];

  // === 阻挡块（锁定时间）===
  static const Color blockLight = Color(0xFFE8E8EE);
  static const Color blockDark = Color(0xFF2A2A3A);
}

/// 文字样式
class AppTextStyles {
  static const String fontFamily = 'SystemDefault'; // 使用系统字体，中文显示更好

  static TextStyle get displayLarge => const TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      );

  static TextStyle get titleLarge => const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      );

  static TextStyle get titleMedium => const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
      );

  static TextStyle get bodyMedium => const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.5,
      );

  static TextStyle get labelSmall => const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      );
}

class AppTheme {
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
          surface: AppColors.surfaceLight,
          onSurface: const Color(0xFF1C1B1F),
        ),
        scaffoldBackgroundColor: AppColors.bgLight,
        cardColor: AppColors.surfaceLight,
        cardTheme: CardThemeData(
          elevation: 0,
          color: AppColors.surfaceLight,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.bgLight,
          foregroundColor: Color(0xFF1C1B1F),
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1C1B1F),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surfaceVariantLight,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
        navigationRailTheme: const NavigationRailThemeData(
          backgroundColor: AppColors.surfaceLight,
          selectedIconTheme: IconThemeData(color: AppColors.primary),
          indicatorColor: AppColors.primaryContainer,
        ),
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primaryDark,
          brightness: Brightness.dark,
          surface: AppColors.surfaceDark,
          onSurface: const Color(0xFFE6E1E5),
        ),
        scaffoldBackgroundColor: AppColors.bgDark,
        cardColor: AppColors.surfaceDark,
        cardTheme: CardThemeData(
          elevation: 0,
          color: AppColors.surfaceDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.bgDark,
          foregroundColor: Color(0xFFE6E1E5),
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Color(0xFFE6E1E5),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryDark,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surfaceVariantDark,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
        navigationRailTheme: const NavigationRailThemeData(
          backgroundColor: AppColors.surfaceDark,
          selectedIconTheme: IconThemeData(color: AppColors.primaryDark),
          indicatorColor: AppColors.primaryContainerDark,
        ),
      );
}
