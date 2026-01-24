// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:google_fonts/google_fonts.dart';

// Project imports:
import 'package:openlib/ui/extensions.dart';

final secondaryColor = '#FB0101'.toColor();

ThemeData lightTheme = ThemeData(
  primaryColor: Colors.white,
  colorScheme: ColorScheme.light(
    primary: Colors.white,
    secondary: secondaryColor,
    tertiary: Colors.black,
    tertiaryContainer: '#F2F2F2'.toColor(),
  ),
  textTheme: TextTheme(
      displayLarge: const TextStyle(
        color: Colors.black,
        fontWeight: FontWeight.bold,
        fontSize: 21,
      ),
      displayMedium: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.bold,
        color: Colors.black,
        overflow: TextOverflow.ellipsis,
      ),
      headlineMedium: TextStyle(
        color: "#595E60".toColor(),
      ),
      headlineSmall: TextStyle(
        color: "#7F7F7F".toColor(),
      )),
  fontFamily: GoogleFonts.nunito().fontFamily,
  useMaterial3: true,
  textSelectionTheme: TextSelectionThemeData(
    selectionColor: secondaryColor,
    selectionHandleColor: secondaryColor,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    labelStyle: TextStyle(color: Colors.grey[700]),
    enabledBorder: OutlineInputBorder(
      borderSide: BorderSide(color: Colors.grey[300]!),
      borderRadius: BorderRadius.circular(8),
    ),
    focusedBorder: OutlineInputBorder(
      borderSide: BorderSide(color: secondaryColor),
      borderRadius: BorderRadius.circular(8),
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: secondaryColor,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    ),
  ),
);

ThemeData darkTheme = ThemeData(
  primaryColor: Colors.black,
  scaffoldBackgroundColor: Colors.black,
  canvasColor: Colors.black,
  colorScheme: ColorScheme.dark(
    primary: Colors.white,
    onPrimary: Colors.black,
    secondary: secondaryColor,
    tertiary: Colors.white,
    tertiaryContainer: '#141414'.toColor(),
    surface: Colors.black,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.black,
    foregroundColor: Colors.white,
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: secondaryColor,
      foregroundColor: Colors.white,
    ),
  ),
  textTheme: TextTheme(
    displayLarge: const TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.bold,
      fontSize: 21,
    ),
    displayMedium: const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.bold,
      color: Colors.white,
      overflow: TextOverflow.ellipsis,
    ),
    headlineMedium: TextStyle(
      color: "#F5F5F5".toColor(),
    ),
    headlineSmall: TextStyle(
      color: "#E8E2E2".toColor(),
    ),
  ),
  fontFamily: GoogleFonts.nunito().fontFamily,
  useMaterial3: true,
  textSelectionTheme: TextSelectionThemeData(
    selectionColor: secondaryColor,
    selectionHandleColor: secondaryColor,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor:
        const Color(0xFF1E1E1E), // Slightly lighter than black for contrast
    labelStyle: TextStyle(color: Colors.grey[400]),
    hintStyle: TextStyle(color: Colors.grey[600]),
    enabledBorder: OutlineInputBorder(
      borderSide: BorderSide(color: Colors.grey[800]!),
      borderRadius: BorderRadius.circular(8),
    ),
    focusedBorder: OutlineInputBorder(
      borderSide: BorderSide(color: secondaryColor),
      borderRadius: BorderRadius.circular(8),
    ),
  ),
);
