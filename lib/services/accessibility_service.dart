import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/constants.dart'; // UPDATED: Added import for signal status constants

class AccessibilityService {
  static final AccessibilityService _instance = AccessibilityService._internal();
  factory AccessibilityService() => _instance;
  AccessibilityService._internal();

  // Screen reader announcements
  static void announceForAccessibility(BuildContext context, String message) {
    // Use HapticFeedback for accessibility announcements
    HapticFeedback.mediumImpact();
    // In a real app, you would use a proper screen reader service
    // For now, we'll use haptic feedback to indicate announcements
  }

  // Announce page changes
  static void announcePageChange(BuildContext context, String pageName) {
    announceForAccessibility(context, 'Navigated to $pageName');
  }

  // Announce button actions
  static void announceButtonAction(BuildContext context, String action) {
    announceForAccessibility(context, action);
  }

  // Announce form field changes
  static void announceFormFieldChange(BuildContext context, String fieldName, String value) {
    announceForAccessibility(context, '$fieldName changed to $value');
  }

  // Announce loading states
  static void announceLoading(BuildContext context, String operation) {
    announceForAccessibility(context, '$operation in progress');
  }

  // Announce completion
  static void announceCompletion(BuildContext context, String operation) {
    announceForAccessibility(context, '$operation completed');
  }

  // Announce errors
  static void announceError(BuildContext context, String error) {
    announceForAccessibility(context, 'Error: $error');
  }

  // Announce success
  static void announceSuccess(BuildContext context, String message) {
    announceForAccessibility(context, 'Success: $message');
  }

  // Get accessible text for status
  static String getAccessibleStatusText(String status) {
    switch (status.toLowerCase()) {
      case 'online':
        return 'Device is online and connected';
      case 'offline':
        return 'Device is offline and disconnected';
      case 'connecting':
        return 'Device is attempting to connect';
      case 'error':
        return 'Connection error occurred';
      case 'active':
        return 'Session is active and running';
      case 'inactive':
        return 'Session is inactive or stopped';
      case 'loading':
        return 'Loading data, please wait';
      case 'success':
        return 'Operation completed successfully';
      case 'failed':
        return 'Operation failed to complete';
      default:
        return status;
    }
  }

  // Get accessible text for location
  static String getAccessibleLocationText(double? latitude, double? longitude, double? accuracy) {
    if (latitude == null || longitude == null) {
      return 'Location unavailable';
    }
    
    final latText = 'Latitude ${latitude.toStringAsFixed(4)}';
    final lngText = 'Longitude ${longitude.toStringAsFixed(4)}';
    final accuracyText = accuracy != null ? 'Accuracy plus or minus ${accuracy.toStringAsFixed(1)} meters' : '';
    
    return '$latText, $lngText. $accuracyText'.trim();
  }

  // Get accessible text for battery
  static String getAccessibleBatteryText(int? batteryLevel) {
    if (batteryLevel == null) {
      return 'Battery level unknown';
    }
    
    if (batteryLevel <= 10) {
      return 'Battery critically low at $batteryLevel percent';
    } else if (batteryLevel <= 20) {
      return 'Battery low at $batteryLevel percent';
    } else if (batteryLevel <= 50) {
      return 'Battery at $batteryLevel percent';
    } else {
      return 'Battery good at $batteryLevel percent';
    }
  }

  // Get accessible text for signal strength (API compatible)
  static String getAccessibleSignalText(String signalStatus) {
    switch (signalStatus.toLowerCase()) {
      case SignalStatus.strong:
        return 'Signal status is strong';  // API compatible
      case SignalStatus.weak:
        return 'Signal status is weak';    // API compatible
      case SignalStatus.poor:
        return 'Signal status is poor';    // API compatible
      default:
        return 'Signal status is $signalStatus';
    }
  }

  // Get accessible text for permissions
  static String getAccessiblePermissionText(String permission, bool isGranted) {
    final status = isGranted ? 'granted' : 'denied';
    return '$permission permission is $status';
  }

  // Get accessible text for time
  static String getAccessibleTimeText(DateTime time) {
    final hour = time.hour;
    final minute = time.minute;
    final ampm = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final minuteText = minute < 10 ? '0$minute' : minute.toString();
    
    return '$hour12:$minuteText $ampm';
  }

  // Get accessible text for duration
  static String getAccessibleDurationText(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    
    if (hours > 0) {
      return '$hours hours, $minutes minutes, $seconds seconds';
    } else if (minutes > 0) {
      return '$minutes minutes, $seconds seconds';
    } else {
      return '$seconds seconds';
    }
  }

  // Get accessible text for count
  static String getAccessibleCountText(int count, String itemName) {
    if (count == 0) {
      return 'No $itemName';
    } else if (count == 1) {
      return '1 $itemName';
    } else {
      return '$count ${itemName}s';
    }
  }

  // Get accessible text for percentage
  static String getAccessiblePercentageText(double percentage) {
    return '${percentage.toStringAsFixed(1)} percent';
  }

  // Get accessible text for size
  static String getAccessibleSizeText(int bytes) {
    if (bytes < 1024) {
      return '$bytes bytes';
    } else if (bytes < 1024 * 1024) {
      final kb = (bytes / 1024).toStringAsFixed(1);
      return '$kb kilobytes';
    } else if (bytes < 1024 * 1024 * 1024) {
      final mb = (bytes / (1024 * 1024)).toStringAsFixed(1);
      return '$mb megabytes';
    } else {
      final gb = (bytes / (1024 * 1024 * 1024)).toStringAsFixed(1);
      return '$gb gigabytes';
    }
  }

  // Get accessible text for temperature
  static String getAccessibleTemperatureText(double temperature, String unit) {
    final tempText = temperature.toStringAsFixed(1);
    return '$tempText degrees $unit';
  }

  // Get accessible text for speed
  static String getAccessibleSpeedText(double speed, String unit) {
    final speedText = speed.toStringAsFixed(1);
    return '$speedText $unit';
  }

  // Get accessible text for distance
  static String getAccessibleDistanceText(double distance, String unit) {
    final distanceText = distance.toStringAsFixed(1);
    return '$distanceText $unit';
  }

  // Get accessible text for weight
  static String getAccessibleWeightText(double weight, String unit) {
    final weightText = weight.toStringAsFixed(1);
    return '$weightText $unit';
  }

  // Get accessible text for volume
  static String getAccessibleVolumeText(double volume, String unit) {
    final volumeText = volume.toStringAsFixed(1);
    return '$volumeText $unit';
  }

  // Get accessible text for pressure
  static String getAccessiblePressureText(double pressure, String unit) {
    final pressureText = pressure.toStringAsFixed(1);
    return '$pressureText $unit';
  }

  // Get accessible text for angle
  static String getAccessibleAngleText(double angle, String unit) {
    final angleText = angle.toStringAsFixed(1);
    return '$angleText degrees';
  }

  // Get accessible text for frequency
  static String getAccessibleFrequencyText(double frequency, String unit) {
    final frequencyText = frequency.toStringAsFixed(1);
    return '$frequencyText $unit';
  }

  // Get accessible text for power
  static String getAccessiblePowerText(double power, String unit) {
    final powerText = power.toStringAsFixed(1);
    return '$powerText $unit';
  }

  // Get accessible text for energy
  static String getAccessibleEnergyText(double energy, String unit) {
    final energyText = energy.toStringAsFixed(1);
    return '$energyText $unit';
  }

  // Get accessible text for force
  static String getAccessibleForceText(double force, String unit) {
    final forceText = force.toStringAsFixed(1);
    return '$forceText $unit';
  }

  // Get accessible text for torque
  static String getAccessibleTorqueText(double torque, String unit) {
    final torqueText = torque.toStringAsFixed(1);
    return '$torqueText $unit';
  }

  // Get accessible text for density
  static String getAccessibleDensityText(double density, String unit) {
    final densityText = density.toStringAsFixed(1);
    return '$densityText $unit';
  }

  // Get accessible text for viscosity
  static String getAccessibleViscosityText(double viscosity, String unit) {
    final viscosityText = viscosity.toStringAsFixed(1);
    return '$viscosityText $unit';
  }

  // Get accessible text for conductivity
  static String getAccessibleConductivityText(double conductivity, String unit) {
    final conductivityText = conductivity.toStringAsFixed(1);
    return '$conductivityText $unit';
  }

  // Get accessible text for resistivity
  static String getAccessibleResistivityText(double resistivity, String unit) {
    final resistivityText = resistivity.toStringAsFixed(1);
    return '$resistivityText $unit';
  }

  // Get accessible text for capacitance
  static String getAccessibleCapacitanceText(double capacitance, String unit) {
    final capacitanceText = capacitance.toStringAsFixed(1);
    return '$capacitanceText $unit';
  }

  // Get accessible text for inductance
  static String getAccessibleInductanceText(double inductance, String unit) {
    final inductanceText = inductance.toStringAsFixed(1);
    return '$inductanceText $unit';
  }

  // Get accessible text for resistance
  static String getAccessibleResistanceText(double resistance, String unit) {
    final resistanceText = resistance.toStringAsFixed(1);
    return '$resistanceText $unit';
  }

  // Get accessible text for voltage
  static String getAccessibleVoltageText(double voltage, String unit) {
    final voltageText = voltage.toStringAsFixed(1);
    return '$voltageText $unit';
  }

  // Get accessible text for current
  static String getAccessibleCurrentText(double current, String unit) {
    final currentText = current.toStringAsFixed(1);
    return '$currentText $unit';
  }
}
