import 'package:flutter/material.dart';

class AppColors {
  // Modern light business theme
  static const Color seed = Color(0xFF1F4FA8);
  static const Color primaryDark = Color(0xFF143B82);
  static const Color primaryLight = Color(0xFF4B77C9);

  // Light surfaces
  static const Color scaffoldBackground = Color(0xFFF5F8FC);
  static const Color appShellHeaderBackground = Color(0xFFFDFEFF);
  static const Color appShellHeaderBorder = Color(0xFFD6E0EE);

  // Semantic highlights for collaborative cards/panels
  static const Color coworkerHighlight = Color(0xFFEAF2FF);
  static const Color aiSummaryBackground = Color(0xFFF3F7FD);

  // Base colors
  static const Color white = Colors.white;
  static const Color transparent = Colors.transparent;
  static const Color black12 = Color(0x1F0F172A);
  static const Color error = Color(0xFFEF4444);

  // Status colors
  static Color statusDone = const Color(0xFF1F9D55);
  static Color statusOverdue = const Color(0xFFD14343);
  static Color statusInWork = const Color(0xFFCC8B1B);

  static Color projectStatusDefault = const Color(0xFF1F4FA8);

  // Kanban columns
  static Color kanbanInWorkColumn = const Color(0xFFFFF8E8);
  static Color kanbanDoneColumn = const Color(0xFFEAF8F0);
  static Color kanbanOverdueColumn = const Color(0xFFFFEFEF);
  static Color kanbanDropHover = const Color(
    0xFF1F4FA8,
  ).withValues(alpha: 0.12);

  // Calendar colors
  static Color calendarTextMuted = const Color(0xFF5B6B82);
  static Color calendarInfoBackground = const Color(0xFFF8FBFF);
  static Color calendarInfoBorder = const Color(0xFFD6E0EE);
  static Color calendarToday = const Color(0xFF1F4FA8);
  static Color calendarSelected = const Color(0xFF4B77C9);
  static Color calendarMarker = const Color(0xFFFFB84D);

  // Provider colors
  static Color providerGoogle = const Color(0xFFEA4335);
  static Color providerMicrosoft = const Color(0xFF0078D4);
  static Color providerOffice = const Color(0xFF737373);

  // Admin/Action colors
  static Color adminDropZoneBorder = const Color(0xFFD6E0EE);

  // Additional utilities
  static Color divider = const Color(0xFFD6E0EE);
  static Color textSecondary = const Color(0xFF5B6B82);
  static Color textTertiary = const Color(0xFF8A9BB4);
  static Color hoverLight = const Color(0xFFECF2FA);
}
