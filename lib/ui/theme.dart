// Foot Zone — couleurs et thème. Tableau tactique : bleu cobalt, plots orange, traits de craie.
import 'package:flutter/material.dart';

class Pal {
  final Color board, board2, cone, bg, surface, ink, muted, line, qual, win, draw, loss, yellow, red;
  const Pal({
    required this.board,
    required this.board2,
    required this.cone,
    required this.bg,
    required this.surface,
    required this.ink,
    required this.muted,
    required this.line,
    required this.qual,
    required this.win,
    required this.draw,
    required this.loss,
    required this.yellow,
    required this.red,
  });

  static const light = Pal(
    board: Color(0xFF1B3B8F),
    board2: Color(0xFF234AA8),
    cone: Color(0xFFEC6417),
    bg: Color(0xFFEEF1F6),
    surface: Color(0xFFFFFFFF),
    ink: Color(0xFF111A2E),
    muted: Color(0xFF5A6478),
    line: Color(0xFFD7DDE8),
    qual: Color(0xFFE7EEFC),
    win: Color(0xFF1F8A4C),
    draw: Color(0xFF8A93A6),
    loss: Color(0xFFC8352B),
    yellow: Color(0xFFF4C21B),
    red: Color(0xFFD7342A),
  );

  static const dark = Pal(
    board: Color(0xFF22408F),
    board2: Color(0xFF6D8CFF),
    cone: Color(0xFFFF7A2E),
    bg: Color(0xFF0C1220),
    surface: Color(0xFF151D30),
    ink: Color(0xFFE8ECF5),
    muted: Color(0xFF98A2B8),
    line: Color(0xFF27324A),
    qual: Color(0xFF1B2846),
    win: Color(0xFF3FB56E),
    draw: Color(0xFF7D8699),
    loss: Color(0xFFE5574C),
    yellow: Color(0xFFF4C21B),
    red: Color(0xFFE5483D),
  );

  static Pal of(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? dark : light;
}

ThemeData buildTheme(Brightness b) {
  final p = b == Brightness.dark ? Pal.dark : Pal.light;
  final scheme = ColorScheme.fromSeed(seedColor: p.board, brightness: b).copyWith(
    primary: p.board,
    onPrimary: Colors.white,
    secondary: p.cone,
    onSecondary: Colors.white,
    surface: p.surface,
    onSurface: p.ink,
    error: p.red,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: b);
  return base.copyWith(
    scaffoldBackgroundColor: p.bg,
    textTheme: base.textTheme.apply(bodyColor: p.ink, displayColor: p.ink),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 54),
        backgroundColor: p.cone,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        foregroundColor: p.ink,
        side: BorderSide(color: p.line, width: 2),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.ink,
      contentTextStyle: TextStyle(color: p.bg, fontWeight: FontWeight.w600, fontSize: 15),
      actionTextColor: p.cone,
    ),
    dividerTheme: DividerThemeData(color: p.line, space: 1, thickness: 1),
  );
}

/// Barre du haut aux couleurs de Foot Zone.
class FzAppBar extends AppBar {
  FzAppBar({super.key, super.title, super.actions, super.toolbarHeight})
      : super(
          backgroundColor: Pal.light.board,
          foregroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: .2),
        );
}
