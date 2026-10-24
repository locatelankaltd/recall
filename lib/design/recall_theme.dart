import 'package:flutter/material.dart';

/// Original Recall palette. Use [RecallPalette.of] for semantic surfaces so
/// state styling remains readable in both appearance modes.
abstract final class RecallColors {
  static const paper = Color(0xFFF6F2EA);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF172E34);
  static const muted = Color(0xFF52666B);
  static const petrol = Color(0xFF14535B);
  static const coral = Color(0xFFA43F2A);
  static const green = Color(0xFF286544);
  static const amber = Color(0xFF775216);
  static const soft = Color(0xFFDCEAE8);
  static const border = Color(0xFFD9DFDA);
}

@immutable
class RecallPalette extends ThemeExtension<RecallPalette> {
  const RecallPalette({
    required this.paper,
    required this.panel,
    required this.ink,
    required this.muted,
    required this.line,
    required this.accent,
    required this.change,
    required this.changeSurface,
    required this.confirmed,
    required this.confirmedSurface,
    required this.pending,
    required this.pendingSurface,
  });
  final Color paper;
  final Color panel;
  final Color ink;
  final Color muted;
  final Color line;
  final Color accent;
  final Color change;
  final Color changeSurface;
  final Color confirmed;
  final Color confirmedSurface;
  final Color pending;
  final Color pendingSurface;

  static RecallPalette of(BuildContext context) =>
      Theme.of(context).extension<RecallPalette>() ?? light;

  static const light = RecallPalette(
    paper: RecallColors.paper,
    panel: RecallColors.surface,
    ink: RecallColors.ink,
    muted: RecallColors.muted,
    line: RecallColors.border,
    accent: RecallColors.petrol,
    change: RecallColors.coral,
    changeSurface: Color(0xFFF7E7DF),
    confirmed: RecallColors.green,
    confirmedSurface: Color(0xFFE4EFE6),
    pending: RecallColors.amber,
    pendingSurface: Color(0xFFFFEFD1),
  );
  static const dark = RecallPalette(
    paper: Color(0xFF101F23),
    panel: Color(0xFF182C31),
    ink: Color(0xFFF1F3EB),
    muted: Color(0xFFA9BCBB),
    line: Color(0xFF354B50),
    accent: Color(0xFFA2D6D6),
    change: Color(0xFFF5A18C),
    changeSurface: Color(0xFF492E29),
    confirmed: Color(0xFFA6D6B7),
    confirmedSurface: Color(0xFF203D30),
    pending: Color(0xFFEAC87E),
    pendingSurface: Color(0xFF40351F),
  );

  @override
  RecallPalette copyWith({
    Color? paper,
    Color? panel,
    Color? ink,
    Color? muted,
    Color? line,
    Color? accent,
    Color? change,
    Color? changeSurface,
    Color? confirmed,
    Color? confirmedSurface,
    Color? pending,
    Color? pendingSurface,
  }) => RecallPalette(
    paper: paper ?? this.paper,
    panel: panel ?? this.panel,
    ink: ink ?? this.ink,
    muted: muted ?? this.muted,
    line: line ?? this.line,
    accent: accent ?? this.accent,
    change: change ?? this.change,
    changeSurface: changeSurface ?? this.changeSurface,
    confirmed: confirmed ?? this.confirmed,
    confirmedSurface: confirmedSurface ?? this.confirmedSurface,
    pending: pending ?? this.pending,
    pendingSurface: pendingSurface ?? this.pendingSurface,
  );

  @override
  RecallPalette lerp(covariant RecallPalette? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return RecallPalette(
      paper: mix(paper, other.paper),
      panel: mix(panel, other.panel),
      ink: mix(ink, other.ink),
      muted: mix(muted, other.muted),
      line: mix(line, other.line),
      accent: mix(accent, other.accent),
      change: mix(change, other.change),
      changeSurface: mix(changeSurface, other.changeSurface),
      confirmed: mix(confirmed, other.confirmed),
      confirmedSurface: mix(confirmedSurface, other.confirmedSurface),
      pending: mix(pending, other.pending),
      pendingSurface: mix(pendingSurface, other.pendingSurface),
    );
  }
}

abstract final class RecallTheme {
  static ThemeData get light => _build(Brightness.light, RecallPalette.light);
  static ThemeData get dark => _build(Brightness.dark, RecallPalette.dark);

  static ThemeData _build(Brightness brightness, RecallPalette p) {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: RecallColors.petrol,
          brightness: brightness,
        ).copyWith(
          primary: p.accent,
          onPrimary: brightness == Brightness.light
              ? Colors.white
              : const Color(0xFF102E34),
          secondary: p.change,
          surface: p.panel,
          onSurface: p.ink,
          onSurfaceVariant: p.muted,
          outline: p.line,
          outlineVariant: p.line,
          primaryContainer: brightness == Brightness.light
              ? RecallColors.soft
              : const Color(0xFF24474D),
          onPrimaryContainer: p.ink,
        );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
    );
    final text = base.textTheme
        .apply(bodyColor: p.ink, displayColor: p.ink)
        .copyWith(
          displaySmall: TextStyle(
            fontSize: 36,
            height: 1.13,
            fontWeight: FontWeight.w600,
            letterSpacing: -1.4,
            color: p.ink,
          ),
          headlineLarge: TextStyle(
            fontSize: 32,
            height: 1.15,
            fontWeight: FontWeight.w600,
            letterSpacing: -1.1,
            color: p.ink,
          ),
          headlineMedium: TextStyle(
            fontSize: 28,
            height: 1.2,
            fontWeight: FontWeight.w600,
            letterSpacing: -.8,
            color: p.ink,
          ),
          headlineSmall: TextStyle(
            fontSize: 24,
            height: 1.25,
            fontWeight: FontWeight.w600,
            letterSpacing: -.5,
            color: p.ink,
          ),
          titleLarge: TextStyle(
            fontSize: 21,
            height: 1.3,
            fontWeight: FontWeight.w600,
            letterSpacing: -.35,
            color: p.ink,
          ),
          titleMedium: TextStyle(
            fontSize: 16,
            height: 1.4,
            fontWeight: FontWeight.w600,
            color: p.ink,
          ),
          bodyLarge: TextStyle(fontSize: 16, height: 1.5, color: p.ink),
          bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: p.ink),
          bodySmall: TextStyle(fontSize: 12, height: 1.45, color: p.muted),
          labelLarge: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
          labelMedium: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            height: 1.3,
            color: p.muted,
          ),
        );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );
    return base.copyWith(
      scaffoldBackgroundColor: p.paper,
      textTheme: text,
      extensions: [p],
      dividerColor: p.line,
      iconTheme: IconThemeData(color: p.ink, size: 24),
      appBarTheme: AppBarTheme(
        backgroundColor: p.paper,
        foregroundColor: p.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: p.panel,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: shape.copyWith(side: BorderSide(color: p.line)),
      ),
      dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: text.labelLarge,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 52),
          foregroundColor: p.accent,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          side: BorderSide(color: p.line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: p.accent,
          textStyle: text.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: p.ink,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 76,
        elevation: 0,
        backgroundColor: p.paper,
        surfaceTintColor: Colors.transparent,
        indicatorColor: brightness == Brightness.light
            ? RecallColors.soft
            : const Color(0xFF24474D),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStatePropertyAll(
          text.labelMedium!.copyWith(color: p.ink),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.panel,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        labelStyle: TextStyle(color: p.muted),
        hintStyle: TextStyle(color: p.muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: p.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: p.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: p.accent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.panel,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.ink,
        contentTextStyle: TextStyle(color: p.paper),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        iconColor: p.muted,
        textColor: p.ink,
        minVerticalPadding: 12,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: p.accent),
    );
  }
}
