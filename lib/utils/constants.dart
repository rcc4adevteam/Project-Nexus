import 'package:flutter/material.dart';

class AppConstants {
  static const String baseUrl = 'https://asia-southeast1-nexuspolice-13560.cloudfunctions.net/';
  static const String appTitle = 'Philippine National Police';
  static const String appMotto = 'SERVICE • HONOR • JUSTICE';
  static const String developerCredit = 'DEVELOPED BY RCC4A AND RICTMD4A';
  static const int locationWarningNotificationId = 99;
}

// Signal status constants based on API specification
class SignalStatus {
  static const String strong = 'strong';  // Combined strong and moderate (API compatible)
  static const String weak = 'weak';
  static const String poor = 'poor';
  
  // Helper method to get all valid signal statuses
  static List<String> get allValues => [strong, weak, poor];
  
  // Helper method to get color for signal status
  static Color getColor(String status) {
    switch (status) {
      case strong:
        return Colors.green;
      case weak:
        return Colors.orange;
      case poor:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}

class AppThemes {
  static final ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    primaryColor: const Color(0xFFFFFFFF),
    scaffoldBackgroundColor: const Color(0xFFF2F2F7),
    cardColor: const Color(0xFFFFFFFF),
    colorScheme: const ColorScheme.light().copyWith(
      secondary: const Color(0xFF007AFF),
      primary: const Color(0xFF007AFF),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    cardTheme: CardThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: Color(0xFF000000)),
      bodyMedium: TextStyle(color: Color(0xFF000000)),
    ),
  );

  static final ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    primaryColor: const Color(0xFF000000),
    scaffoldBackgroundColor: const Color(0xFF000000),
    cardColor: const Color(0xFF1C1C1E),
    colorScheme: const ColorScheme.dark().copyWith(
      secondary: const Color(0xFF0A84FF),
      primary: const Color(0xFF0A84FF),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    cardTheme: CardThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: Color(0xFFFFFFFF)),
      bodyMedium: TextStyle(color: Color(0xFFFFFFFF)),
    ),
  );
}

// UPDATED: Optimized settings for movement-based updates
class AppSettings {
  // Movement-based adaptive intervals
  static const Duration fastMovingInterval = Duration(seconds: 5);     // >28 km/h
  static const Duration movingInterval = Duration(seconds: 15);        // >7 km/h
  static const Duration slowMovingInterval = Duration(seconds: 30);    // >3.6 km/h
  static const Duration stationaryInterval = Duration(minutes: 2);     // Stationary, good battery
  static const Duration lowBatteryInterval = Duration(minutes: 5);     // Stationary, low battery
  
  // Session monitoring (reduced from 5s to save data)
  static const Duration sessionCheckInterval = Duration(seconds: 30);
  
  // NEW: Signal status monitoring intervals
  static const Duration signalUpdateInterval = Duration(seconds: 30);
  
  // Background service intervals
  static const Duration backgroundUpdateInterval = Duration(minutes: 1);
  static const Duration heartbeatInterval = Duration(minutes: 5);
  
  // Movement detection thresholds
  static const double stationarySpeedThreshold = 1.0;    // m/s (~3.6 km/h)
  static const double movingSpeedThreshold = 2.0;        // m/s (~7.2 km/h)  
  static const double fastMovingSpeedThreshold = 2.78;   // m/s (~10.0 km/h)
  static const double movementDistanceThreshold = 10.0;  // meters
  
  // Battery optimization thresholds
  static const int lowBatteryThreshold = 20;             // %
  static const int criticalBatteryThreshold = 10;       // %
  
  // Data optimization settings
  static const int coordinatePrecision = 5;              // decimal places (~1m accuracy)
  static const int speedPrecision = 1;                   // decimal places
  static const int batteryChangeThreshold = 5;           // % change to trigger update
  
  // Legacy compatibility (deprecated - use adaptive intervals above)
  @Deprecated('Use adaptive intervals instead')
  static const Duration apiUpdateInterval = Duration(seconds: 30);
  
  @Deprecated('Use adaptive intervals instead')
  static const Duration locationTimeout = Duration(seconds: 30);
  
  @Deprecated('Use adaptive intervals instead')
  static const Duration batteryUpdateInterval = Duration(minutes: 1);
  
  @Deprecated('Use adaptive intervals instead')
  static const Duration networkUpdateInterval = Duration(minutes: 1);
  
  @Deprecated('Use movementDistanceThreshold instead')
  static const int distanceFilter = 10;
}