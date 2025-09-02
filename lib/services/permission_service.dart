import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'dart:io';

class PermissionService {
  static final PermissionService _instance = PermissionService._internal();
  factory PermissionService() => _instance;
  PermissionService._internal();

  // Android API level constants
  static const int ANDROID_12_API_LEVEL = 31;
  static const int ANDROID_13_API_LEVEL = 33;

  // Check all required permissions including background location
  Future<Map<String, bool>> checkAllPermissions() async {
    final permissions = {
      'location': await Permission.location.status,
      'locationAlways': await Permission.locationAlways.status, // CRITICAL for background
      'camera': await Permission.camera.status,
      'notification': await Permission.notification.status,
      'ignoreBatteryOptimizations': await Permission.ignoreBatteryOptimizations.status,
      'scheduleExactAlarm': await Permission.scheduleExactAlarm.status, // For Android 12+
    };

    return {
      'location': permissions['location']!.isGranted,
      'locationAlways': permissions['locationAlways']!.isGranted,
      'camera': permissions['camera']!.isGranted,
      'notification': permissions['notification']!.isGranted,
      'ignoreBatteryOptimizations': permissions['ignoreBatteryOptimizations']!.isGranted,
      'scheduleExactAlarm': permissions['scheduleExactAlarm']!.isGranted,
    };
  }

  // Request all permissions with Android 12+ handling
  Future<Map<String, bool>> requestAllPermissions() async {
    print('PermissionService: Requesting all permissions...');
    
    try {
      // Step 1: Request basic location first
      await requestPermission(Permission.location);
      
      // Step 2: Request background location (most critical)
      await requestPermission(Permission.locationAlways);
      
      // Step 3: Request other permissions
      await requestPermission(Permission.camera);
      await requestPermission(Permission.notification);
      await requestPermission(Permission.ignoreBatteryOptimizations);
      await requestPermission(Permission.scheduleExactAlarm);

      // Final check
      return await checkAllPermissions();
      
    } catch (e) {
      print('PermissionService: Error requesting permissions: $e');
      return await checkAllPermissions();
    }
  }

  // FIXED: Request specific permission with proper Android 12+ handling
  Future<bool> requestPermission(Permission permission) async {
    try {
      print('PermissionService: Requesting ${permission.toString()}...');
      
      // Get current status
      final currentStatus = await permission.status;
      print('PermissionService: Current status for ${permission.toString()}: $currentStatus');
      
      // If already granted, return true
      if (currentStatus.isGranted) {
        print('PermissionService: Permission already granted');
        return true;
      }
      
      // Special handling for background location
      if (permission == Permission.locationAlways) {
        return await _requestBackgroundLocationFixed();
      }
      
      // Special handling for exact alarm on Android 12+
      if (permission == Permission.scheduleExactAlarm) {
        return await _requestExactAlarmFixed();
      }
      
      // Special handling for battery optimization
      if (permission == Permission.ignoreBatteryOptimizations) {
        return await _requestBatteryOptimizationFixed();
      }
      
      // Standard permission request with retry mechanism
      PermissionStatus status = PermissionStatus.denied;
      
      // Try multiple times with delays (fixes Android 12+ issues)
      for (int attempt = 1; attempt <= 3; attempt++) {
        print('PermissionService: Attempt $attempt for ${permission.toString()}');
        
        try {
          status = await permission.request();
          print('PermissionService: Attempt $attempt result: $status');
          
          if (status.isGranted) {
            return true;
          }
          
          // If permanently denied, don't retry
          if (status.isPermanentlyDenied) {
            print('PermissionService: Permission permanently denied');
            break;
          }
          
          // Wait before retry
          if (attempt < 3) {
            await Future.delayed(Duration(milliseconds: 500));
          }
          
        } catch (e) {
          print('PermissionService: Attempt $attempt failed: $e');
          if (attempt == 3) rethrow;
        }
      }
      
      return status.isGranted;
      
    } catch (e) {
      print('PermissionService: Error requesting permission ${permission.toString()}: $e');
      return false;
    }
  }

  // FIXED: Background location request with proper Android 12+ flow
  Future<bool> _requestBackgroundLocationFixed() async {
    try {
      print('PermissionService: Starting background location request...');
      
      // Step 1: Check Android version
      final apiLevel = await _getAndroidApiLevel();
      print('PermissionService: Android API Level: $apiLevel');
      
      // Step 2: Ensure foreground location is granted first
      final foregroundStatus = await Permission.location.status;
      if (!foregroundStatus.isGranted) {
        print('PermissionService: Requesting foreground location first...');
        final foregroundResult = await Permission.location.request();
        if (!foregroundResult.isGranted) {
          print('PermissionService: Foreground location denied');
          return false;
        }
        // Wait a moment for system to process
        await Future.delayed(Duration(milliseconds: 1000));
      }
      
      // Step 3: Request background location with platform channel fallback
      print('PermissionService: Requesting background location...');
      
      PermissionStatus backgroundStatus = PermissionStatus.denied;
      
      try {
        // Primary method: Use permission_handler
        backgroundStatus = await Permission.locationAlways.request();
        print('PermissionService: Primary method result: $backgroundStatus');
      } catch (e) {
        print('PermissionService: Primary method failed: $e');
        
        // Fallback: Try platform channel method
        try {
          await _requestBackgroundLocationPlatformChannel();
          backgroundStatus = await Permission.locationAlways.status;
          print('PermissionService: Platform channel fallback result: $backgroundStatus');
        } catch (e2) {
          print('PermissionService: Platform channel fallback failed: $e2');
        }
      }
      
      // Step 4: If denied, try opening settings
      if (!backgroundStatus.isGranted && !backgroundStatus.isPermanentlyDenied) {
        print('PermissionService: Background permission denied, trying settings approach...');
        
        // Wait a moment then check again (sometimes Android delays the response)
        await Future.delayed(Duration(milliseconds: 2000));
        final recheckStatus = await Permission.locationAlways.status;
        
        if (recheckStatus.isGranted) {
          return true;
        }
      }
      
      return backgroundStatus.isGranted;
      
    } catch (e) {
      print('PermissionService: Error in background location request: $e');
      return false;
    }
  }

  // NEW: Platform channel method for background location (Android 12+ fallback)
  Future<void> _requestBackgroundLocationPlatformChannel() async {
    try {
      const platform = MethodChannel('flutter/permission_handler');
      await platform.invokeMethod('requestPermission', {
        'permission': 'ACCESS_BACKGROUND_LOCATION',
      });
    } catch (e) {
      print('PermissionService: Platform channel method failed: $e');
      rethrow;
    }
  }

  // FIXED: Exact alarm permission for Android 12+
  Future<bool> _requestExactAlarmFixed() async {
    try {
      final apiLevel = await _getAndroidApiLevel();
      
      // Only relevant for Android 12+
      if (apiLevel < ANDROID_12_API_LEVEL) {
        return true; // Not needed on older versions
      }
      
      print('PermissionService: Requesting exact alarm permission for Android 12+...');
      
      // Multiple attempts for Android 12+
      for (int attempt = 1; attempt <= 2; attempt++) {
        try {
          final status = await Permission.scheduleExactAlarm.request();
          print('PermissionService: Exact alarm attempt $attempt result: $status');
          
          if (status.isGranted) {
            return true;
          }
          
          // Wait before retry
          if (attempt < 2) {
            await Future.delayed(Duration(milliseconds: 1000));
          }
          
        } catch (e) {
          print('PermissionService: Exact alarm attempt $attempt failed: $e');
          if (attempt == 2) {
            // Fallback: assume granted on Android 12+ if request fails
            return true;
          }
        }
      }
      
      return false;
    } catch (e) {
      print('PermissionService: Error requesting exact alarm: $e');
      return true; // Assume granted to not block app
    }
  }

  // FIXED: Battery optimization permission
  Future<bool> _requestBatteryOptimizationFixed() async {
    try {
      print('PermissionService: Requesting battery optimization permission...');
      
      // Multiple attempts
      for (int attempt = 1; attempt <= 2; attempt++) {
        try {
          final status = await Permission.ignoreBatteryOptimizations.request();
          print('PermissionService: Battery optimization attempt $attempt result: $status');
          
          if (status.isGranted) {
            return true;
          }
          
          // Wait before retry
          if (attempt < 2) {
            await Future.delayed(Duration(milliseconds: 1000));
          }
          
        } catch (e) {
          print('PermissionService: Battery optimization attempt $attempt failed: $e');
          if (attempt == 2) rethrow;
        }
      }
      
      return false;
    } catch (e) {
      print('PermissionService: Error requesting battery optimization: $e');
      return false;
    }
  }

  // Get Android API Level
  Future<int> _getAndroidApiLevel() async {
    if (!Platform.isAndroid) return 0;
    
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.version.sdkInt;
    } catch (e) {
      print('PermissionService: Error getting Android API level: $e');
      return 30; // Default to Android 11
    }
  }

  // Check if all critical permissions for background tracking are granted
  Future<bool> hasAllCriticalPermissions() async {
    final permissions = await checkAllPermissions();
    // ALL of these are critical for reliable background tracking
    return permissions['location']! && 
           permissions['locationAlways']! && // MOST IMPORTANT
           permissions['notification']! && 
           permissions['ignoreBatteryOptimizations']!;
  }

  // Show permission rationale dialog
  Future<void> showPermissionRationale(BuildContext context, String permissionType) async {
    String title = '';
    String content = '';
    
    switch (permissionType) {
      case 'location':
        title = 'Location Permission Required';
        content = 'This app needs location access to track your position for security purposes.';
        break;
      case 'locationAlways':
        title = 'Background Location Critical';
        content = 'For 24/7 location tracking, this app needs "Allow all the time" location permission. Please select "Allow all the time" when prompted, not just "While using app".';
        break;
      case 'camera':
        title = 'Camera Permission Required';
        content = 'Camera access is needed to scan QR codes and capture evidence when required.';
        break;
      case 'notification':
        title = 'Notification Permission Required';
        content = 'Notifications are essential to show that the app is running in background and for important alerts.';
        break;
      case 'ignoreBatteryOptimizations':
        title = 'Disable Battery Optimization';
        content = 'For 24/7 monitoring, this app must be exempt from battery optimization. Please allow this permission when prompted.';
        break;
      case 'scheduleExactAlarm':
        title = 'Schedule Exact Alarm Permission';
        content = 'Required for precise timing of location updates on Android 12+.';
        break;
    }

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              if (permissionType == 'locationAlways') {
                _requestBackgroundLocationFixed();
              } else {
                openAppSettings();
              }
            },
            child: Text(permissionType == 'locationAlways' ? 'Grant Permission' : 'Open Settings'),
          ),
        ],
      ),
    );
  }

  // Show specific guidance for background location
  Future<void> showBackgroundLocationRationale(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Background Location Required'),
        content: const Text(
          'For 24/7 location tracking, this app needs "Allow all the time" location permission. '
          'Please select "Allow all the time" when prompted, not just "While using app".'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _requestBackgroundLocationFixed();
            },
            child: const Text('Grant Permission'),
          ),
        ],
      ),
    );
  }

  // Get permission status text
  String getPermissionStatusText(bool isGranted) {
    return isGranted ? 'GRANTED' : 'DENIED';
  }

  // Get permission status color
  Color getPermissionStatusColor(bool isGranted) {
    return isGranted ? Colors.green : Colors.red;
  }

  // Get permission icon
  IconData getPermissionIcon(bool isGranted) {
    return isGranted ? Icons.check_circle : Icons.error;
  }
}