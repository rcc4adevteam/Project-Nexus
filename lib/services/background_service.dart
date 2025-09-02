import 'dart:async';
import 'dart:ui';
import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'api_service.dart';
import '../utils/constants.dart'; // UPDATED: Added import for signal status constants

const notificationChannelId = 'pnp_location_service';
const notificationId = 888;
const heartbeatChannelId = 'pnp_heartbeat_service';
const heartbeatNotificationId = 999;
const offlineNotificationId = 997;
const reconnectionNotificationId = 996;
const aggressiveDisconnectionId = 995;
const emergencyAlertId = 994;
const sessionTerminatedId = 893;

// FIXED: Global timer management with proper cleanup
class _BackgroundServiceTimers {
  static Timer? _heartbeatTimer;
  static Timer? _offlineNotificationTimer;
  static Timer? _aggressiveConnectivityTimer;
  static Timer? _emergencyAlertTimer;
  static Timer? _sessionMonitoringTimer;
  static Timer? _mainLocationTimer;
  static Timer? _locationServiceTimer;
  static Timer? _emergencyUpdateTimer; // Removed usage after feature removal
  
  // FIXED: Cleanup all timers
  static void cleanupAllTimers() {
    print('BackgroundService: Cleaning up all timers...');
    
    _heartbeatTimer?.cancel();
    _offlineNotificationTimer?.cancel();
    _aggressiveConnectivityTimer?.cancel();
    _emergencyAlertTimer?.cancel();
    _sessionMonitoringTimer?.cancel();
    _mainLocationTimer?.cancel();
    _locationServiceTimer?.cancel();
    _emergencyUpdateTimer?.cancel();
    
    // Reset all timer references to null
    _heartbeatTimer = null;
    _offlineNotificationTimer = null;
    _aggressiveConnectivityTimer = null;
    _emergencyAlertTimer = null;
    _sessionMonitoringTimer = null;
    _mainLocationTimer = null;
    _locationServiceTimer = null;
    _emergencyUpdateTimer = null;
    
    print('BackgroundService: All timers cleaned up successfully');
  }
  
  // FIXED: Safe timer creation with cleanup
  static Timer createPeriodicTimer(Duration duration, void Function(Timer) callback) {
    return Timer.periodic(duration, callback);
  }
  
  // FIXED: Safe timer creation for one-time use
  static Timer createTimer(Duration duration, void Function() callback) {
    return Timer(duration, callback);
  }
}

final _notifications = FlutterLocalNotificationsPlugin();
bool _isOnline = true;
bool _wasOfflineNotificationSent = false;
int _disconnectionCount = 0;
DateTime? _lastConnectionCheck;
DateTime? _serviceStartTime;
bool _sessionActive = true;
DateTime? _lastSessionCheck;
StreamSubscription<ConnectivityResult>? _connectivitySubscription;

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  // Notification channels setup
  const AndroidNotificationChannel mainChannel = AndroidNotificationChannel(
    notificationChannelId,
    'PNP Location Service',
    description: 'Keeps the PNP Device Monitor running in the background',
    importance: Importance.low,
    enableVibration: false,
    playSound: false,
  );

  const AndroidNotificationChannel heartbeatChannel = AndroidNotificationChannel(
    heartbeatChannelId,
    'PNP Heartbeat Service',
    description: 'Shows app is alive and tracking',
    importance: Importance.min,
    enableVibration: false,
    playSound: false,
  );

  AndroidNotificationChannel sessionTerminatedChannel = AndroidNotificationChannel(
    'session_terminated_bg',
    'Session Terminated',
    description: 'Notifications when session is terminated from another device',
    importance: Importance.max,
    enableVibration: true,
    enableLights: true,
    ledColor: Color(0xFFFF6600),
    playSound: true,
    showBadge: true,
  );

  AndroidNotificationChannel criticalDisconnectionChannel = AndroidNotificationChannel(
    'critical_disconnection_bg',
    'Critical Background Disconnection',
    description: 'Critical disconnection alerts from background service',
    importance: Importance.max,
    enableVibration: true,
    enableLights: true,
    ledColor: Color(0xFFFF0000),
    playSound: true,
    sound: RawResourceAndroidNotificationSound('alarm_sound'),
    showBadge: true,
  );

  AndroidNotificationChannel emergencyChannel = AndroidNotificationChannel(
    'emergency_bg_override',
    'Emergency Background Override',
    description: 'Emergency notifications that override all restrictions',
    importance: Importance.max,
    enableVibration: true,
    enableLights: true,
    ledColor: Color(0xFFFF4500),
    playSound: true,
    sound: RawResourceAndroidNotificationSound('alarm_sound'),
    showBadge: true,
  );

  AndroidNotificationChannel reconnectionChannel = AndroidNotificationChannel(
    'reconnection_channel',
    'Auto-Reconnection',
    description: 'Notifications for automatic reconnection events',
    importance: Importance.high,
    enableVibration: false,
    playSound: false,
  );

  await _notifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(mainChannel);
      
  await _notifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(heartbeatChannel);

  await _notifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(sessionTerminatedChannel);

  await _notifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(criticalDisconnectionChannel);

  await _notifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(emergencyChannel);

  await _notifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(reconnectionChannel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: notificationChannelId,
      initialNotificationTitle: 'PNP Device Monitor - ENHANCED MODE',
      initialNotificationContent: 'Enhanced monitoring enabled • Location tracking active',
      foregroundServiceNotificationId: notificationId,
      autoStartOnBoot: true,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

// Session terminated notification
Future<void> _showSessionTerminatedNotification() async {
  AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'session_terminated_bg',
    'SESSION TERMINATED',
    channelDescription: 'Session terminated from another device',
    importance: Importance.max,
    priority: Priority.max,
    ongoing: false,
    autoCancel: false,
    fullScreenIntent: true,
    category: AndroidNotificationCategory.alarm,
    visibility: NotificationVisibility.public,
    color: Color(0xFFFF6600),
    colorized: true,
    enableVibration: true,
    vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
    enableLights: true,
    ledColor: Color(0xFFFF6600),
    ledOnMs: 1000,
    ledOffMs: 500,
    playSound: true,
    showWhen: true,
    channelShowBadge: true,
  );
  
  NotificationDetails details = NotificationDetails(android: androidDetails);
  
  await _notifications.show(
    sessionTerminatedId,
    '🚨 Session Terminated',
    'Your deployment code was logged in from another device. Background service stopped. Time: ${DateTime.now().toString().substring(11, 19)}',
    details,
  );
  
  print('BackgroundService: SESSION TERMINATED notification sent');
}

// Aggressive disconnection notification
Future<void> _showAggressiveDisconnectionNotification() async {
  AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'critical_disconnection_bg',
    'CRITICAL DISCONNECTION',
    channelDescription: 'Critical disconnection detected by background service',
    importance: Importance.max,
    priority: Priority.max,
    ongoing: true,
    autoCancel: false,
    fullScreenIntent: true,
    category: AndroidNotificationCategory.alarm,
    visibility: NotificationVisibility.public,
    color: Color(0xFFFF0000),
    colorized: true,
    enableVibration: true,
    vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000, 500, 1000]),
    enableLights: true,
    ledColor: Color(0xFFFF0000),
    ledOnMs: 1000,
    ledOffMs: 500,
    sound: RawResourceAndroidNotificationSound('alarm_sound'),
    playSound: true,
    showWhen: true,
    channelShowBadge: true,
    groupKey: 'CRITICAL_BG_ALERTS',
    setAsGroupSummary: true,
    timeoutAfter: null,
  );
  
  NotificationDetails details = NotificationDetails(android: androidDetails);
  
  await _notifications.show(
    aggressiveDisconnectionId,
    '🚨 BACKGROUND SERVICE: Connection Lost',
    'ENHANCED ALERT: Device disconnected (#$_disconnectionCount). Background tracking continues. Time: ${DateTime.now().toString().substring(11, 19)}',
    details,
  );
  
  _wasOfflineNotificationSent = true;
  print('BackgroundService: ENHANCED disconnection notification sent');
}

// Emergency alert
Future<void> _showEmergencyBackgroundAlert() async {
  final offlineMinutes = _lastConnectionCheck != null 
      ? DateTime.now().difference(_lastConnectionCheck!).inMinutes 
      : 0;

  AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'emergency_bg_override',
    'EMERGENCY BACKGROUND ALERT',
    channelDescription: 'Emergency background alert for extended disconnection',
    importance: Importance.max,
    priority: Priority.max,
    ongoing: true,
    autoCancel: false,
    fullScreenIntent: true,
    category: AndroidNotificationCategory.alarm,
    visibility: NotificationVisibility.public,
    color: Color(0xFFFF4500),
    colorized: true,
    enableVibration: true,
    vibrationPattern: Int64List.fromList([0, 1500, 1000, 1500, 1000, 1500]),
    enableLights: true,
    ledColor: Color(0xFFFF4500),
    ledOnMs: 1500,
    ledOffMs: 500,
    sound: RawResourceAndroidNotificationSound('alarm_sound'),
    playSound: true,
    showWhen: true,
    channelShowBadge: true,
    timeoutAfter: null,
  );
  
  NotificationDetails details = NotificationDetails(android: androidDetails);
  
  await _notifications.show(
    emergencyAlertId,
    '🆘 EMERGENCY: Extended Offline ($offlineMinutes min)',
    'CRITICAL: Device offline for $offlineMinutes minutes. Background service maintaining GPS tracking. Check connection immediately.',
    details,
  );
  
  print('BackgroundService: EMERGENCY alert sent - offline for $offlineMinutes minutes');
}

// Connection restored notification
Future<void> _showConnectionRestoredNotification() async {
  AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'reconnection_channel',
    'Connection Restored',
    channelDescription: 'Network connection restored notification',
    importance: Importance.high,
    priority: Priority.high,
    enableVibration: false,
    visibility: NotificationVisibility.public,
    autoCancel: true,
    color: Color(0xFF00FF00),
    colorized: true,
  );
  
  NotificationDetails details = NotificationDetails(android: androidDetails);
  
  await _notifications.show(
    reconnectionNotificationId,
    '✅ Background Service: Connection Restored',
    'Network restored successfully. Location sync resumed. Disconnection count: $_disconnectionCount',
    details,
  );
  
  // Auto-dismiss after 3 seconds
  _BackgroundServiceTimers.createTimer(const Duration(seconds: 3), () {
    _notifications.cancel(reconnectionNotificationId);
  });
}

// Heartbeat notification
Future<void> _showHeartbeatNotification() async {
  final uptime = _serviceStartTime != null 
      ? DateTime.now().difference(_serviceStartTime!).inMinutes 
      : 0;

  final sessionStatus = _sessionActive ? 'ACTIVE' : 'TERMINATED';

  AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    heartbeatChannelId,
    'PNP Enhanced Heartbeat',
    channelDescription: 'Shows enhanced monitoring is active',
    importance: Importance.min,
    priority: Priority.min,
    showWhen: true,
    ongoing: false,
    autoCancel: true,
  );
  
  NotificationDetails details = NotificationDetails(android: androidDetails);
  
  await _notifications.show(
    heartbeatNotificationId,
    'PNP Enhanced Monitoring Active',
    'Uptime: ${uptime}min • Disconnections: $_disconnectionCount • Status: ${_isOnline ? "ONLINE" : "OFFLINE"} • Session: $sessionStatus • ${DateTime.now().toString().substring(11, 16)}',
    details,
  );
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  _serviceStartTime = DateTime.now();
  
  print('BackgroundService: Starting ENHANCED monitoring system with proper timer management...');
  
  // FIXED: Clean up any existing timers before starting new ones
  _BackgroundServiceTimers.cleanupAllTimers();
  
  // Force enable wake lock with maximum priority
  try {
    await WakelockPlus.enable();
    print('BackgroundService: ENHANCED wake lock enabled');
  } catch (e) {
    print('BackgroundService: FAILED to enable enhanced wakelock: $e');
  }

  // FIXED: Session monitoring timer with proper management
  _BackgroundServiceTimers._sessionMonitoringTimer = _BackgroundServiceTimers.createPeriodicTimer(
    const Duration(seconds: 5), 
    (timer) async {
      await _checkSessionStatus();
    }
  );
  print('BackgroundService: Session monitoring timer started');

  // FIXED: Enhanced connectivity monitoring with proper cleanup
  await _initializeConnectivityMonitoring();

  // FIXED: Emergency monitoring timer
  _BackgroundServiceTimers._emergencyAlertTimer = _BackgroundServiceTimers.createPeriodicTimer(
    const Duration(minutes: 2), 
    (timer) {
      if (!_isOnline) {
        _showEmergencyBackgroundAlert();
      }
    }
  );
  print('BackgroundService: Emergency monitoring timer started');

  // FIXED: Enhanced heartbeat timer
  _BackgroundServiceTimers._heartbeatTimer = _BackgroundServiceTimers.createPeriodicTimer(
    const Duration(minutes: 5), 
    (timer) {
      _showHeartbeatNotification();
    }
  );
  print('BackgroundService: Heartbeat timer started');

  // FIXED: Handle service stop requests with proper cleanup
  service.on('stopService').listen((event) async {
    print('BackgroundService: Stop ENHANCED service requested - starting cleanup...');
    
    // Stop all timers first
    _BackgroundServiceTimers.cleanupAllTimers();
    
    // Clean up connectivity monitoring
    await _cleanupConnectivityMonitoring();
    
    // Disable wake lock
    try {
      await WakelockPlus.disable();
      print('BackgroundService: Wake lock disabled');
    } catch (e) {
      print('BackgroundService: Error disabling wake lock: $e');
    }
    
    print('BackgroundService: Cleanup completed, stopping service...');
    service.stopSelf();
  });

  // FIXED: Main location tracking loop with proper timer management
  _BackgroundServiceTimers._mainLocationTimer = _BackgroundServiceTimers.createPeriodicTimer(
    const Duration(seconds: 15), 
    (timer) async {
      await _processLocationUpdate(service, timer);
    }
  );
  print('BackgroundService: Main location tracking timer started');

  // ENHANCED: Location service monitoring timer
  _BackgroundServiceTimers._locationServiceTimer = _BackgroundServiceTimers.createPeriodicTimer(
    const Duration(seconds: 10), 
    (timer) async {
      await _checkLocationServiceStatus();
    }
  );
  print('BackgroundService: Location service monitoring timer started');

  // Emergency update feature removed
}

// FIXED: Initialize connectivity monitoring with proper cleanup
Future<void> _initializeConnectivityMonitoring() async {
  try {
    print('BackgroundService: Initializing connectivity monitoring...');
    
    // Clean up existing subscription first
    await _cleanupConnectivityMonitoring();
    
    // Layer 1: System connectivity listener
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (ConnectivityResult result) {
        _handleConnectivityChange(result, 'System Listener');
      },
      onError: (error) {
        print('BackgroundService: Connectivity subscription error: $error');
      },
      cancelOnError: false,
    );
    
    // Layer 2: Aggressive polling timer
    _BackgroundServiceTimers._aggressiveConnectivityTimer = _BackgroundServiceTimers.createPeriodicTimer(
      const Duration(seconds: 3), 
      (timer) async {
        try {
          final result = await Connectivity().checkConnectivity();
          final isCurrentlyOnline = result != ConnectivityResult.none;
          
          if (_isOnline != isCurrentlyOnline) {
            _handleConnectivityChange(result, 'Enhanced Polling');
          }
          
          _lastConnectionCheck = DateTime.now();
        } catch (e) {
          print('BackgroundService: Enhanced connectivity check failed: $e');
          // Assume offline if check fails
          if (_isOnline) {
            _handleConnectivityChange(ConnectivityResult.none, 'Check Failure');
          }
        }
      }
    );
    
    print('BackgroundService: Connectivity monitoring initialized successfully');
  } catch (e) {
    print('BackgroundService: Error initializing connectivity monitoring: $e');
  }
}

// FIXED: Cleanup connectivity monitoring
Future<void> _cleanupConnectivityMonitoring() async {
  try {
    print('BackgroundService: Cleaning up connectivity monitoring...');
    
    // Cancel connectivity subscription
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    
    print('BackgroundService: Connectivity monitoring cleaned up');
  } catch (e) {
    print('BackgroundService: Error cleaning up connectivity monitoring: $e');
  }
}

// Check session status with timeout handling
Future<void> _checkSessionStatus() async {
  try {
    _lastSessionCheck = DateTime.now();
    
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final deploymentCode = prefs.getString('deploymentCode');

    if (token == null || deploymentCode == null) {
      print('BackgroundService: No credentials for session check');
      return;
    }

    print('BackgroundService: Checking session status... (${_lastSessionCheck!.toString().substring(11, 19)})');

    // Add timeout to session check
    final statusResponse = await ApiService.checkStatus(token, deploymentCode)
        .timeout(const Duration(seconds: 8));
    
    if (statusResponse.success && statusResponse.data != null) {
      final isLoggedIn = statusResponse.data!['isLoggedIn'] ?? false;
      
      if (!isLoggedIn && _sessionActive) {
        print('BackgroundService: 🚨 SESSION TERMINATED BY ANOTHER DEVICE');
        _sessionActive = false;
        
        // Clear credentials
        // Keep token persistent across logouts as requested
        await prefs.remove('deploymentCode');
        await prefs.setBool('isTokenLocked', false);
        
        // Show session terminated notification
        await _showSessionTerminatedNotification();
        
        print('BackgroundService: Session terminated, background service will stop');
        
      } else if (isLoggedIn) {
        if (!_sessionActive) {
          print('BackgroundService: Session restored');
          _sessionActive = true;
        }
        print('BackgroundService: ✅ Session still active');
      }
    } else {
      print('BackgroundService: Could not verify session: ${statusResponse.message}');
    }
  } on TimeoutException catch (e) {
    print('BackgroundService: Session check timeout: $e');
  } catch (e) {
    print('BackgroundService: Session check failed: $e');
    // Don't change session status on network errors
  }
}

// Handle connectivity changes with enhanced notifications
void _handleConnectivityChange(ConnectivityResult result, String source) {
  final wasOnline = _isOnline;
  _isOnline = result != ConnectivityResult.none;
  
  print('BackgroundService: ENHANCED connectivity change via $source - $result (${_isOnline ? "online" : "offline"})');
  
  if (!_isOnline && wasOnline) {
    // Connection lost - ENHANCED response
    _disconnectionCount++;
    print('BackgroundService: ENHANCED CONNECTION LOST (#$_disconnectionCount)');
    
    // Cancel existing offline notification timer
    _BackgroundServiceTimers._offlineNotificationTimer?.cancel();
    
    // IMMEDIATE enhanced notification
    _showAggressiveDisconnectionNotification();
    
    // PERSISTENT notifications every 10 seconds
    _BackgroundServiceTimers._offlineNotificationTimer = _BackgroundServiceTimers.createPeriodicTimer(
      const Duration(seconds: 10), 
      (timer) {
        _showAggressiveDisconnectionNotification();
      }
    );
    
  } else if (_isOnline && !wasOnline) {
    // Connection restored - Cancel enhanced alerts
    print('BackgroundService: ENHANCED connection restored');
    
    // Cancel offline notification timer
    _BackgroundServiceTimers._offlineNotificationTimer?.cancel();
    _BackgroundServiceTimers._offlineNotificationTimer = null;
    
    if (_wasOfflineNotificationSent) {
      _notifications.cancel(aggressiveDisconnectionId);
      _notifications.cancel(emergencyAlertId);
      _showConnectionRestoredNotification();
      _wasOfflineNotificationSent = false;
    }
  }
}

// FIXED: Process location update with proper error handling
Future<void> _processLocationUpdate(ServiceInstance service, Timer timer) async {
  try {
    // Check if session is still active before processing
    if (!_sessionActive) {
      print('BackgroundService: Session terminated, stopping location tracking');
      timer.cancel();
      
      // Stop the service gracefully
      _BackgroundServiceTimers.cleanupAllTimers();
      service.stopSelf();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final deploymentCode = prefs.getString('deploymentCode');

    if (token == null || deploymentCode == null) {
      print('BackgroundService: No credentials found, stopping enhanced service');
      timer.cancel();
      _BackgroundServiceTimers.cleanupAllTimers();
      service.stopSelf();
      return;
    }

    // Get high-precision location with enhanced retry
    final position = await _getCurrentLocationWithEnhancedRetry();
    final now = DateTime.now();
    final timeString = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";

    // Get GPS status message
    String statusMessage = "⚠️ GPS searching... • $timeString";

    if (position != null) {
      statusMessage = "📍 ENHANCED • Lat: ${position.latitude.toStringAsFixed(4)} • $timeString";
      
      // Log the status for debugging
      print('BackgroundService: $statusMessage');
      
      // Only attempt to send if online AND session is active
      if (_isOnline && _sessionActive) {
        try {
          final battery = Battery();
          final batteryLevel = await battery.batteryLevel;

          // Send location update to server
          final result = await ApiService.updateLocation(
            token: token,
            deploymentCode: deploymentCode,
            position: position,
            batteryLevel: batteryLevel,
            signal: await _getSignalStatus(),
          );

          if (result.success) {
            print('BackgroundService: Location update sent successfully');
          } else {
            print('BackgroundService: Location update failed: ${result.message}');
          }
        } catch (e) {
          print('BackgroundService: Error sending location update: $e');
        }
      }
    } else {
      print('BackgroundService: No GPS signal available');
    }
  } catch (e) {
    print('BackgroundService: Error in location update process: $e');
  }
}

// ENHANCED: Check location service status in background
Future<void> _checkLocationServiceStatus() async {
  try {
    // Check if location services are enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    
    // Check location permissions
    LocationPermission permission = await Geolocator.checkPermission();
    bool hasPermission = permission == LocationPermission.whileInUse || 
                        permission == LocationPermission.always;
    
    // Check if location access is compromised
    if (!serviceEnabled || !hasPermission) {
      print('BackgroundService: 🚨 LOCATION SERVICE COMPROMISED - Service: $serviceEnabled, Permission: $permission');
      
      // Show critical location alert notification
      await _showCriticalLocationAlert();
    }
  } catch (e) {
    print('BackgroundService: Error checking location service status: $e');
  }
}

// Show critical location alert notification
Future<void> _showCriticalLocationAlert() async {
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'location_alert_channel',
    'Location Service Compromised',
    channelDescription: 'Critical alert for location service disconnection',
    importance: Importance.max,
    priority: Priority.max,
    enableVibration: true,
    sound: RawResourceAndroidNotificationSound('alarm_sound'),
    visibility: NotificationVisibility.public,
    ongoing: true,
    autoCancel: false,
    fullScreenIntent: true,
    color: Color(0xFFFF0000),
    colorized: true,
  );
  
  const NotificationDetails details = NotificationDetails(android: androidDetails);
  
  await _notifications.show(
    1003, // Critical location alert notification ID
    '🚨 CRITICAL: Location Service Compromised',
    'GPS/Location access lost in background! Device tracking compromised. Immediate action required.',
    details,
  );
}

// Helper function to get current location with enhanced retry
Future<Position?> _getCurrentLocationWithEnhancedRetry() async {
  try {
    // Check location permissions first
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        print('BackgroundService: Location permission denied');
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      print('BackgroundService: Location permission permanently denied');
      return null;
    }

    // Check if location services are enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print('BackgroundService: Location services are disabled');
      return null;
    }

    // Get current position with high accuracy
    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 10),
    );

    return position;
  } catch (e) {
    print('BackgroundService: Error getting location: $e');
    return null;
  }
}

// Helper function to get signal status using API service
Future<String> _getSignalStatus() async {
  try {
    // Use the improved API-based signal detection
    return await ApiService.getSignalStatus();
  } catch (e) {
    print('BackgroundService: Error getting signal status: $e');
    return SignalStatus.poor;
  }
}

// Safe background service start function
Future<void> startBackgroundServiceSafely() async {
  try {
    print('BackgroundService: Starting background service safely...');
    
    final service = FlutterBackgroundService();
    final isRunning = await service.isRunning();
    
    if (!isRunning) {
      await service.startService();
      print('BackgroundService: Background service started successfully');
    } else {
      print('BackgroundService: Background service already running');
    }
  } catch (e) {
    print('BackgroundService: Error starting background service: $e');
    // Don't throw - allow app to continue without background service
  }
}

// Emergency update feature removed

// Safe background service stop function
Future<void> stopBackgroundServiceSafely() async {
  try {
    print('BackgroundService: Stopping background service safely...');
    
    final service = FlutterBackgroundService();
    final isRunning = await service.isRunning();
    
    if (isRunning) {
      service.invoke('stopService');
      print('BackgroundService: Background service stop requested');
    } else {
      print('BackgroundService: Background service not running');
    }
  } catch (e) {
    print('BackgroundService: Error stopping background service: $e');
    // Don't throw - allow app to continue
  }
}