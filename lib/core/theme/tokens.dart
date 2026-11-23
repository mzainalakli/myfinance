import 'package:flutter/material.dart';

/// Token desain: spasi, radius, ukuran sentuh.
class Tk {
  static const double s2 = 2, s4 = 4, s8 = 8, s12 = 12, s16 = 16, s24 = 24, s32 = 32;
  static const double rSm = 8, rMd = 12, rLg = 20, rXl = 28;
  static const double touch = 48;
  /// Ruang bawah daftar di samping FAB: tinggi FAB (56) + margin (16) + napas (16). Scaffold sudah
  /// mengangkat FAB di atas bar navigasi, jadi safe area bawah tidak perlu ditambah lagi.
  static const double fabClearance = 88;
  static const double maxContentWidth = 640;
  static const Color seed = Color(0xFF0F766E); // satu warna aksen (teal)
  static const Color incomeLight = Color(0xFF15803D);
  static const Color incomeDark = Color(0xFF4ADE80);
  static const Color expenseLight = Color(0xFFB91C1C);
  static const Color expenseDark = Color(0xFFF87171);
}

/// Warna semantik masuk/keluar mengikuti tema.
extension SemanticColors on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get incomeColor => isDark ? Tk.incomeDark : Tk.incomeLight;
  Color get expenseColor => isDark ? Tk.expenseDark : Tk.expenseLight;
}
