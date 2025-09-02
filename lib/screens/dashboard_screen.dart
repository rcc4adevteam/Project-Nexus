import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../services/location_service.dart';
import '../services/device_service.dart';
import '../services/api_service.dart';
import '../services/background_service.dart';
import '../services/watchdog_service.dart';
import '../services/wake_lock_service.dart';
import '../services/theme_provider.dart';
import '../services/responsive_ui_service.dart';
import '../services/update_service.dart';
import '../widgets/metric_card.dart';
import '../widgets/auto_size_text.dart';
import '../widgets/update_dialog.dart';
import '../widgets/hero_header.dart';
import '../utils/constants.dart';
import 'login_screen.dart';

class DashboardScreen extends StatefulWidget {
  final String token;
  final String deploymentCode;

  const DashboardScreen({
    super.key,
    required this.token,
    required this.deploymentCode,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with ResponsiveStateMixin {
  final _locationService = LocationService();
  final _deviceService = DeviceService();
  final _watchdogService = WatchdogService();
  final _wakeLockService = WakeLockService();
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  Timer? _apiUpdateTimer;
  Timer? _heartbeatTimer;
  Timer? _statusUpdateTimer;
  Timer? _reconnectionTimer;
  Timer? _sessionVerificationTimer;
  Timer? _locationAlarmTimer;

  bool _isLoading = true;
  bool _isLocationLoading = true;
  
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  int _locationUpdatesSent = 0;
  DateTime? _lastSuccessfulUpdate;
  bool _isOnline = true;

  bool _isCheckingSession = false;
  bool _sessionActive = true;
  DateTime? _lastSessionCheck;
  int _consecutiveSessionFailures = 0;
  static const int _maxSessionFailures = 3;
  static const Duration _sessionCheckTimeout = Duration(seconds: 8);
  static const Duration _sessionRetryDelay = Duration(seconds: 2);

  StreamSubscription<ServiceStatus>? _locationServiceStatusSubscription;
  bool _isLocationServiceEnabled = true;

  // Movement-based adaptive update system
  Position? _lastPosition;
  Duration _currentUpdateInterval = Duration(seconds: 30);
  // Realtime console state
  final List<String> _consoleLines = [];
  static const int _consoleMaxLines = 60;
  void _pushConsole(String message) {
    final now = DateTime.now();
    final time = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
    final line = "$time  $message";
    if (mounted) {
      setState(() {
        _consoleLines.add(line);
        if (_consoleLines.length > _consoleMaxLines) {
          _consoleLines.removeRange(0, _consoleLines.length - _consoleMaxLines);
        }
      });
    } else {
      _consoleLines.add(line);
      if (_consoleLines.length > _consoleMaxLines) {
        _consoleLines.removeRange(0, _consoleLines.length - _consoleMaxLines);
      }
    }
  }
  void _seedConsole() {
    if (_consoleLines.isNotEmpty) return;
    _consoleLines.add(_isOnline ? 'Network: ONLINE' : 'Network: OFFLINE');
    _consoleLines.add('Session: ' + (_sessionActive ? 'ACTIVE' : 'LOST'));
    _consoleLines.add('Battery: ${_deviceService.batteryLevel}%');
    _consoleLines.add('Signal: ${_deviceService.signalStatus.toUpperCase()}');
    if (_lastSuccessfulUpdate != null) {
      _consoleLines.add('Last update: ${_lastSuccessfulUpdate!.toString().substring(11, 19)} (sent: $_locationUpdatesSent)');
    }
  }

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _initializeNotifications();
    _listenForConnectivityChanges();
    _startSessionMonitoring();
    _listenToLocationServiceStatus();
  }

  @override
  void dispose() {
    _cleanupAllTimers();
    _locationAlarmTimer?.cancel();
    _locationService.dispose();
    _deviceService.dispose();
    _watchdogService.stopWatchdog();
    _connectivitySubscription?.cancel();
    _locationServiceStatusSubscription?.cancel();
    super.dispose();
  }

  void _listenToLocationServiceStatus() {
    _locationServiceStatusSubscription = Geolocator.getServiceStatusStream().listen((ServiceStatus status) {
      if (mounted) {
        final isEnabled = (status == ServiceStatus.enabled);

        if (_isLocationServiceEnabled != isEnabled) {
          setState(() {
            _isLocationServiceEnabled = isEnabled;
          });

          if (!isEnabled) {
            _startLocationAlarm();
          } else {
            _stopLocationAlarm();
          }
        }
      }
    });
  }

  void _startLocationAlarm() {
    _locationAlarmTimer?.cancel();
    _showLocationOffNotification();
    _locationAlarmTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _showLocationOffNotification();
    });
    print('Dashboard: Starting location disabled alarm via notifications.');
  }

  void _stopLocationAlarm() {
    _locationAlarmTimer?.cancel();
    _notifications.cancel(AppConstants.locationWarningNotificationId);
    print('Dashboard: Stopping location alarm and clearing notification.');
  }

  Future<void> _showLocationOffNotification() async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'location_alarm_channel',
      'Location Status',
      channelDescription: 'Alarm for when location service is disabled',
      importance: Importance.max,
      priority: Priority.high,
      sound: RawResourceAndroidNotificationSound('alarm_sound'),
      playSound: true,
      ongoing: true,
    );
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await _notifications.show(
      AppConstants.locationWarningNotificationId,
      'Location Service Disabled',
      'Location is required for the app to function correctly. Please turn it back on.',
      platformChannelSpecifics,
    );
  }

  void _cleanupAllTimers() {
    print('Dashboard: Cleaning up all timers...');
    _apiUpdateTimer?.cancel();
    _heartbeatTimer?.cancel();
    _statusUpdateTimer?.cancel();
    _reconnectionTimer?.cancel();
    _sessionVerificationTimer?.cancel();

    _apiUpdateTimer = null;
    _heartbeatTimer = null;
    _statusUpdateTimer = null;
    _reconnectionTimer = null;
    _sessionVerificationTimer = null;

    print('Dashboard: All timers cleaned up successfully');
  }

  void _startSessionMonitoring() {
    print('Dashboard: Starting enhanced session monitoring...');

    _sessionVerificationTimer?.cancel();

    _sessionVerificationTimer = Timer.periodic(
      const Duration(seconds: 30), // Reduced from 5 seconds for optimization
      (timer) => _verifySessionWithTimeout()
    );

    print('Dashboard: Enhanced session monitoring started - checking every 30 seconds');
  }

  Future<void> _verifySessionWithTimeout() async {
    if (_isCheckingSession) {
      print('Dashboard: Session check already in progress, skipping...');
      return;
    }

    _isCheckingSession = true;
    _lastSessionCheck = DateTime.now();

    try {
      print('Dashboard: Starting session verification with timeout... (${_lastSessionCheck!.toString().substring(11, 19)})');
      _pushConsole('Session check started');

      final sessionCheckFuture = ApiService.checkStatus(
        widget.token,
        widget.deploymentCode
      );

      final statusResponse = await sessionCheckFuture.timeout(
        _sessionCheckTimeout,
        onTimeout: () {
          print('Dashboard: Session check timed out after ${_sessionCheckTimeout.inSeconds}s');
          throw TimeoutException('Session check timed out', _sessionCheckTimeout);
        },
      );

      if (statusResponse.success && statusResponse.data != null) {
        final isStillLoggedIn = statusResponse.data!['isLoggedIn'] ?? false;

        _consecutiveSessionFailures = 0;

        if (!isStillLoggedIn && _sessionActive && mounted) {
          print('Dashboard: SESSION TERMINATED BY ANOTHER DEVICE - auto-logging out');
          _sessionActive = false;
          _pushConsole('Session: LOST (another device)');
          await _handleAutomaticLogout();
        } else if (isStillLoggedIn && mounted) {
          if (!_sessionActive) {
            setState(() => _sessionActive = true);
            print('Dashboard: Session restored');
            _pushConsole('Session: RESTORED');
          } else {
            print('Dashboard: Session still active');
            _pushConsole('Session: ACTIVE');
          }
        }
      } else {
        print('Dashboard: Session check failed: ${statusResponse.message}');
        await _handleSessionCheckFailure('API error: ${statusResponse.message}');
        _pushConsole('Session check error: ${statusResponse.message}');
      }

    } on TimeoutException catch (e) {
      print('Dashboard: Session check timeout: $e');
      await _handleSessionCheckFailure('Timeout: ${e.message}');
      _pushConsole('Session check timeout');

    } catch (e) {
      print('Dashboard: Session verification failed: $e');
      await _handleSessionCheckFailure('Network error: $e');
      _pushConsole('Session check failed: $e');

    } finally {
      _isCheckingSession = false;
    }
  }

  Future<void> _handleSessionCheckFailure(String reason) async {
    _consecutiveSessionFailures++;
    print('Dashboard: Session check failure #$_consecutiveSessionFailures: $reason');

    if (_consecutiveSessionFailures >= _maxSessionFailures) {
      print('Dashboard: Too many consecutive session failures ($_consecutiveSessionFailures/$_maxSessionFailures)');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.warning, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: AutoSizeText(
                    'Session verification issues detected. Check your connection.',
                    style: TextStyle(fontSize: 14),
                    maxLines: 2,
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.orange[700],
            duration: Duration(seconds: 5),
          ),
        );
      }

      _consecutiveSessionFailures = 0;
      await Future.delayed(_sessionRetryDelay);
    }
  }



  Future<void> _clearStoredCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('deploymentCode');
      await prefs.setBool('isTokenLocked', false);
      print('Dashboard: Stored credentials cleared');
    } catch (e) {
      print('Dashboard: Error clearing credentials: $e');
    }
  }

  Future<void> _handleAutomaticLogout() async {
    print('Dashboard: HANDLING AUTOMATIC LOGOUT WITH PROPER CLEANUP');

    try {
      // Step 1: Stop all monitoring immediately
      _sessionVerificationTimer?.cancel();
      _sessionVerificationTimer = null;
      _cleanupAllTimers();

      // Step 2: Stop services
      _locationService.dispose();
      _deviceService.dispose();
      _watchdogService.stopWatchdog();

      // Step 3: Clear credentials
      await _clearStoredCredentials();

      // Step 4: Show dialog and navigate - FIXED to prevent freezing
      if (mounted) {
        // Close any existing dialogs first
        Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
        
        // Show logout dialog with immediate navigation option
        await _showAutomaticLogoutDialogFixed();
      }

    } catch (e) {
      print('Dashboard: Error during automatic logout: $e');
      // Force navigation even if dialog fails
      if (mounted) {
        _forceNavigateToLogin();
      }
    }
  }

  // FIXED: Automatic logout dialog that won't freeze
  Future<void> _showAutomaticLogoutDialogFixed() async {
    if (!mounted) return;

    // Use a completer to ensure we can always navigate
    final Completer<void> dialogCompleter = Completer<void>();
    
    // Auto-dismiss and navigate after 10 seconds if user doesn't click
    Timer(const Duration(seconds: 10), () {
      if (!dialogCompleter.isCompleted) {
        print('Dashboard: Auto-dismissing logout dialog after timeout');
        dialogCompleter.complete();
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
          _forceNavigateToLogin();
        }
      }
    });

    try {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => WillPopScope(
          onWillPop: () async => false, // Prevent back button
          child: AlertDialog(
            title: Row(
              children: [
                Icon(Icons.logout, color: Colors.orange, size: 24),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Session Terminated',
                    style: TextStyle(
                      color: Colors.orange[700],
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Your deployment code "${widget.deploymentCode}" was logged in from another device.',
                          style: TextStyle(
                            color: Colors.orange[700],
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 16),
                Text(
                  'You have been automatically logged out for security. Please login again to continue.',
                  style: TextStyle(fontSize: 14),
                ),
                SizedBox(height: 12),
                Text(
                  'Time: ${DateTime.now().toString().substring(0, 19)}',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                    fontSize: 12,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Auto-redirect in 10 seconds...',
                  style: TextStyle(
                    color: Colors.blue[600],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            actions: [
              // FIXED: Simplified button that always works
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () {
                    print('Dashboard: User clicked Login Again button');
                    if (!dialogCompleter.isCompleted) {
                      dialogCompleter.complete();
                    }
                    // Force navigation immediately
                    _forceNavigateToLogin();
                  },
                  icon: Icon(Icons.login, size: 20),
                  label: Text(
                    'Login Again',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      print('Dashboard: Error showing logout dialog: $e');
      // Always ensure we can navigate
      if (!dialogCompleter.isCompleted) {
        dialogCompleter.complete();
      }
      if (mounted) {
        _forceNavigateToLogin();
      }
    }
  }

  // FIXED: Force navigation that always works
  void _forceNavigateToLogin() {
    if (!mounted) return;
    
    print('Dashboard: Force navigating to login screen...');
    
    try {
      // Remove all routes and go to login
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      print('Dashboard: Error in force navigation: $e');
      // Last resort - try basic navigation
      try {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      } catch (e2) {
        print('Dashboard: Basic navigation also failed: $e2');
      }
    }
  }

  Widget _buildSessionStatusIndicator() {
    final color = _sessionActive ? Colors.green : Colors.red;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: context.responsiveFont(8.0),
        vertical: context.responsiveFont(4.0),
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(context.responsiveFont(12.0)),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Container(
        width: context.responsiveFont(10.0),
        height: context.responsiveFont(10.0),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: color.withOpacity(0.3)),
        ),
      ),
    );
  }

  Future<void> _initializeNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    await _notifications.initialize(initializationSettings);
    
    const AndroidNotificationChannel locationAlarmChannel = AndroidNotificationChannel(
      'location_alarm_channel',
      'Location Status',
      description: 'Alarm for when location service is disabled',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
    );
    
    await _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(locationAlarmChannel);
  }

  void _listenForConnectivityChanges() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((ConnectivityResult result) {
      final wasOnline = _isOnline;
      _isOnline = result != ConnectivityResult.none;

      if (mounted) {
        setState(() {});
      }

      if (!_isOnline && wasOnline) {
        _showConnectionLostNotification();
        _pushConsole('Network changed: OFFLINE');
      } else if (_isOnline && !wasOnline) {
        _handleConnectionRestored();
        _pushConsole('Network changed: ONLINE');
      }
    });
  }

  Future<void> _handleConnectionRestored() async {
    print('Dashboard: Connection restored, attempting to reconnect...');

    await _notifications.cancel(0);

    _showConnectionRestoredNotification();
    _startAdaptivePeriodicUpdates();
    await _sendLocationUpdateSafely();

    print('Dashboard: Automatic reconnection completed');
  }

  Future<void> _showConnectionLostNotification() async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'connectivity_channel',
      'Connectivity',
      channelDescription: 'Channel for connectivity notifications',
      importance: Importance.max,
      priority: Priority.high,
      sound: RawResourceAndroidNotificationSound('alarm_sound'),
      enableVibration: true,
      visibility: NotificationVisibility.public,
      ongoing: true,
      fullScreenIntent: true,
    );
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);
    await _notifications.show(
      0,
      'Network Connection Lost',
      'Device is offline. Location tracking continues but data cannot be sent. Will auto-reconnect when network is available.',
      platformChannelSpecifics,
    );
  }

  Future<void> _showConnectionRestoredNotification() async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'connectivity_channel',
      'Connectivity',
      channelDescription: 'Channel for connectivity notifications',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: false,
      visibility: NotificationVisibility.public,
      autoCancel: true,
    );
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);
    await _notifications.show(
      1,
      'Connection Restored',
      'Network connection restored. Location tracking resumed successfully.',
      platformChannelSpecifics,
    );

    Timer(const Duration(seconds: 3), () {
      _notifications.cancel(1);
    });
  }

  Future<void> _initializeServices() async {
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      _seedConsole();
      await Future.wait([
        _initializeDeviceService(),
        _initializeLocationTracking(),
        _initializeWatchdog(),
        _initializePermanentWakeLock(),
      ], eagerError: false);

      _startAdaptivePeriodicUpdates(); // Use adaptive updates

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: AutoSizeText(
              'Initialization error: ${e.toString()}',
              maxFontSize: getResponsiveFont(14.0),
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _initializeDeviceService() async {
    await _deviceService.initialize();
    if (mounted) {
      setState(() {});

      if (_deviceService.isOnline) {
        print('Dashboard: Device is online, sending immediate status update to webapp');
        _sendLocationUpdateSafely();
      }
    }
  }

  Future<void> _initializeWatchdog() async {
    try {
      await _watchdogService.initialize(
        onAppDead: () {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('App monitoring was interrupted. Restarting services...'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 5),
              ),
            );
            _initializeServices();
          }
        },
      );
      _watchdogService.startWatchdog();
    } catch (e) {
      print('Dashboard: Error initializing watchdog: $e');
    }
  }

  Future<void> _initializePermanentWakeLock() async {
    try {
      await _wakeLockService.initialize();
      await _wakeLockService.forceEnableForCriticalOperation();
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      Timer(const Duration(seconds: 5), () {
        _initializePermanentWakeLock();
      });
    }
  }

  Future<void> _initializeLocationTracking() async {
    if (!mounted) return;

    setState(() => _isLocationLoading = true);

    try {
      final hasAccess = await _locationService.checkLocationRequirements();
      if (hasAccess) {
        await _wakeLockService.forceEnableForCriticalOperation();

        final position = await _locationService.getCurrentPosition(
          accuracy: LocationAccuracy.bestForNavigation,
          timeout: const Duration(seconds: 15),
        );

        if (position != null && mounted) {
          setState(() => _isLocationLoading = false);
        }

        _locationService.startLocationTracking(
          (position) {
            if (mounted) {
              setState(() => _isLocationLoading = false);
            }
          },
        );

        Timer(const Duration(seconds: 20), () {
          if (mounted && _isLocationLoading) {
            setState(() => _isLocationLoading = false);
          }
        });

      } else {
        if (mounted) {
          setState(() => _isLocationLoading = false);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLocationLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: AutoSizeText(
              'Failed to initialize high-precision location: $e',
              maxFontSize: getResponsiveFont(14.0),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // UPDATED: Adaptive periodic updates based on movement
  void _startAdaptivePeriodicUpdates() {
    _apiUpdateTimer?.cancel();
    _heartbeatTimer?.cancel();
    _statusUpdateTimer?.cancel();

    // Start with movement-based adaptive updates
    _scheduleNextAdaptiveUpdate();

    _heartbeatTimer = Timer.periodic(
      const Duration(minutes: 5),
      (timer) {
        _watchdogService.ping();
        _maintainWakeLock();
        if (mounted) {
          setState(() {});
        }
      },
    );

    _statusUpdateTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (mounted) {
        setState(() {});
      }
    });

    _sendLocationUpdateSafely();
  }

  // NEW: Schedule next adaptive update based on movement
  void _scheduleNextAdaptiveUpdate() {
    _apiUpdateTimer = Timer(_currentUpdateInterval, () async {
      await _processAdaptiveLocationUpdate();
      
      // Schedule next update
      if (mounted) {
        _scheduleNextAdaptiveUpdate();
      }
    });
  }

  // NEW: Process adaptive location update with movement detection
  Future<void> _processAdaptiveLocationUpdate() async {
    final position = _locationService.currentPosition;
    if (position == null) return;

    // Calculate optimal interval based on movement
    _currentUpdateInterval = _calculateOptimalUpdateInterval(position);

    // Check if we should send this update
    if (_shouldSendLocationUpdate(position)) {
      await _sendLocationUpdateSafely();
      
      if (mounted) {
        setState(() {
          _lastSuccessfulUpdate = DateTime.now();
          _locationUpdatesSent++;
        });
      }
    } else {
      print('⏭️ Skipped location update - no significant change');
    }

    _lastPosition = position;
  }

  // NEW: Calculate optimal update interval based on movement
  Duration _calculateOptimalUpdateInterval(Position position) {
    final speed = position.speed; // m/s
    final batteryLevel = _deviceService.batteryLevel;
    
    // FAST MOVEMENT: 5 seconds (your requirement)
    if (speed >= 3.9) { // >14 km/h (3.9 m/s = 14.04 km/h)
      return Duration(seconds: 5);
    }
    
    // NORMAL MOVEMENT: 15 seconds
    if (speed >= 2.0) { // >7 km/h
      return Duration(seconds: 15);
    }
    
    // SLOW MOVEMENT: 30 seconds
    if (speed >= 1.0) { // >3.6 km/h
      return Duration(seconds: 30);
    }
    
    // STATIONARY with low battery: 5 minutes
    if (batteryLevel < 20) {
      return Duration(minutes: 5);
    }
    
    // STATIONARY with good battery: 2 minutes
    return Duration(minutes: 2);
  }

  // NEW: Check if we should send location update
  bool _shouldSendLocationUpdate(Position position) {
    if (_lastPosition == null) return true;

    // Calculate distance moved
    final distance = Geolocator.distanceBetween(
      _lastPosition!.latitude,
      _lastPosition!.longitude,
      position.latitude,
      position.longitude,
    );

    // Always send if moving significantly
    if (distance >= 10.0) return true;

    // Always send if speed is high
    if (position.speed >= 2.0) return true;

    // Send if stationary but interval indicates it's time
    return true;
  }

  Future<void> _maintainWakeLock() async {
    final isEnabled = await _wakeLockService.checkWakeLockStatus();
    if (!isEnabled) {
      await _wakeLockService.forceEnableForCriticalOperation();
    }
  }

  Future<void> _sendLocationUpdateSafely() async {
    if (!_isOnline) {
      print('Dashboard: Offline, skipping location update');
      return;
    }

    try {
      await _sendLocationUpdate();
    } catch (e) {
      print('Dashboard: Error sending location update: $e');
    }
  }

  Future<void> _sendLocationUpdate() async {
    final position = _locationService.currentPosition;
    if (position == null) return;

    try {
      _pushConsole('Sending location update...');
      final result = await ApiService.updateLocation(
        token: widget.token,
        deploymentCode: widget.deploymentCode,
        position: position,
        batteryLevel: _deviceService.batteryLevel,
        signal: _deviceService.signalStatus,
      );

      if (result.success) {
        _locationUpdatesSent++;
        _lastSuccessfulUpdate = DateTime.now();
        print('Dashboard: Location update #$_locationUpdatesSent sent successfully');
        _pushConsole('Location sent • total: $_locationUpdatesSent');
      } else {
        print('Dashboard: Location update failed: ${result.message}');
        _pushConsole('Location failed: ${result.message}');

        if (result.message.contains('Session expired') || result.message.contains('logged in')) {
          _handleSessionExpired();
        }
      }
    } catch (e) {
      print('Dashboard: Error sending location update: $e');
      _pushConsole('Location error: $e');
    }
  }

  void _handleSessionExpired() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: AutoSizeText(
          'Session Expired',
          maxFontSize: getResponsiveFont(18.0),
        ),
        content: AutoSizeText(
          'Your session has expired or you have been logged out from another device. Please login again.',
          maxFontSize: getResponsiveFont(14.0),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _performLogout();
            },
            child: AutoSizeText(
              'OK',
              maxFontSize: getResponsiveFont(14.0),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _performLogout() async {
    var connectivityResult = await (Connectivity().checkConnectivity());
    if (connectivityResult == ConnectivityResult.none) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AutoSizeText(
            'No network connection. Please connect to log out.',
            maxFontSize: getResponsiveFont(14.0),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: AutoSizeText(
          'Confirm Logout',
          maxFontSize: getResponsiveFont(18.0),
        ),
        content: AutoSizeText(
          'Are you sure you want to log out?',
          maxFontSize: getResponsiveFont(14.0),
        ),
        actions: [
          TextButton(
            child: AutoSizeText(
              'Cancel',
              maxFontSize: getResponsiveFont(14.0),
            ),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: AutoSizeText(
              'Logout',
              maxFontSize: getResponsiveFont(14.0),
            ),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _executeCancellableAction('Logging out...', () async {
      await ApiService.logout(widget.token, widget.deploymentCode);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('deploymentCode');
      _watchdogService.stopWatchdog();
      try {
        await stopBackgroundServiceSafely();
      } catch (e) {
        print("Dashboard: Error stopping background service: $e");
      }
      await Future.delayed(const Duration(milliseconds: 500));
    });
  }

  Future<void> _executeCancellableAction(String title, Future<void> Function() action) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Card(
          child: Padding(
            padding: context.responsivePadding(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: context.responsiveFont(40.0),
                  height: context.responsiveFont(40.0),
                  child: const CircularProgressIndicator(),
                ),
                SizedBox(height: context.responsiveFont(16.0)),
                AutoSizeText(
                  title,
                  maxFontSize: getResponsiveFont(16.0),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      await action();
    } catch (e) {
      print("Dashboard: Error during action '$title': $e");
    }

    if (mounted) {
      Navigator.of(context).pop();
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  Color _getBatteryColor(BuildContext context) {
    final level = _deviceService.batteryLevel;
    if (level > 50) return Colors.green;
    if (level > 20) return Colors.orange;
    return Colors.red;
  }

  IconData _getBatteryIcon() {
    final level = _deviceService.batteryLevel;
    final state = _deviceService.batteryState;
    if (state.toString().contains('charging')) return Icons.battery_charging_full_rounded;
    if (level > 80) return Icons.battery_full_rounded;
    if (level > 60) return Icons.battery_6_bar_rounded;
    if (level > 40) return Icons.battery_4_bar_rounded;
    if (level > 20) return Icons.battery_2_bar_rounded;
    return Icons.battery_1_bar_rounded;
  }

  Color _getSignalColor(BuildContext context) {
    return SignalStatus.getColor(_deviceService.signalStatus);
  }

  Future<void> _refreshLocation() async {
    setState(() => _isLocationLoading = true);
    try {
      final position = await _locationService.getCurrentPosition();
      if (position != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: AutoSizeText(
              'Location refreshed (±${position.accuracy.toStringAsFixed(1)}m)',
              maxFontSize: getResponsiveFont(14.0),
            ),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: AutoSizeText(
              'Failed to get location.',
              maxFontSize: getResponsiveFont(14.0),
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: AutoSizeText(
              'Failed to refresh location: $e',
              maxFontSize: getResponsiveFont(14.0),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLocationLoading = false);
      }
    }
  }

  Future<void> _refreshDashboard() async {
    print('Dashboard: Starting pull-to-refresh...');

    try {
      await Future.wait([
        _deviceService.refreshDeviceInfo(),
        _refreshLocation(),
        _sendLocationUpdateSafely(),
      ], eagerError: false);

      if (mounted) {
        setState(() {});
      }

      print('Dashboard: Pull-to-refresh completed successfully');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: AutoSizeText(
              'Dashboard refreshed successfully',
              maxFontSize: getResponsiveFont(14.0),
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('Dashboard: Error during pull-to-refresh: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: AutoSizeText(
              'Refresh failed: ${e.toString()}',
              maxFontSize: getResponsiveFont(14.0),
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Stack(
          children: [
            Scaffold(
              appBar: AppBar(
                title: AutoSizeText(
                  'Device Monitor',
                  maxFontSize: getResponsiveFont(20.0),
                ),
                actions: [
                  _buildSessionStatusIndicator(),
                  SizedBox(width: context.responsiveFont(8.0)),
                  IconButton(
                    icon: Icon(
                      Icons.system_update_rounded,
                      size: ResponsiveUIService.getResponsiveIconSize(
                        context: context,
                        baseIconSize: 24.0,
                      ),
                    ),
                    onPressed: _checkForUpdates,
                    tooltip: 'Check for Updates',
                  ),
                  SizedBox(width: context.responsiveFont(8.0)),
                  IconButton(
                    icon: Icon(
                      themeProvider.themeMode == ThemeMode.dark
                          ? Icons.light_mode_rounded
                          : Icons.dark_mode_rounded,
                      size: ResponsiveUIService.getResponsiveIconSize(
                        context: context,
                        baseIconSize: 24.0,
                      ),
                    ),
                    onPressed: () {
                      themeProvider.toggleTheme();
                    },
                    tooltip: 'Toggle Theme',
                  ),
                ],
              ),
              body: _isLoading
                  ? Center(
                      child: SizedBox(
                        width: context.responsiveFont(48.0),
                        height: context.responsiveFont(48.0),
                        child: CircularProgressIndicator(
                          strokeWidth: context.responsiveFont(3.0),
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        HeroHeader(
                          title: 'Device Monitor',
                          subtitle: 'Deployment: ${widget.deploymentCode}',
                          leadingIcon: Icons.shield_rounded,
                          consoleLines: _buildRealtimeConsoleLines(),
                        ),
                        SizedBox(height: context.responsiveFont(8.0)),
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: _refreshDashboard,
                            child: GridView.count(
                              crossAxisCount: ResponsiveUIService.getGridCrossAxisCount(context),
                              padding: context.responsivePadding(),
                              mainAxisSpacing: context.responsiveFont(16.0),
                              crossAxisSpacing: context.responsiveFont(16.0),
                              childAspectRatio: _calculateAspectRatio(),
                              children: [
                                MetricCard(
                                  title: 'Connection',
                                  icon: _isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                                  iconColor: _isOnline ? Colors.green : Colors.red,
                                  value: _isOnline ? 'Online' : 'Offline',
                                  subtitle: _deviceService.getConnectivityDescription(),
                                ),
                                MetricCard(
                                  title: 'Battery',
                                  icon: _getBatteryIcon(),
                                  iconColor: _getBatteryColor(context),
                                  value: '${_deviceService.batteryLevel}%',
                                  subtitle: _deviceService.getBatteryHealthStatus(),
                                  isRealTime: true,
                                ),
                                MetricCard(
                                  title: 'Signal Status', // FIXED: Changed from 'Signal Strength' to 'Signal Status'
                                  icon: Icons.signal_cellular_alt_rounded,
                                  iconColor: _getSignalColor(context),
                                  value: _deviceService.signalStatus.toUpperCase(),
                                  subtitle: '',
                                  isRealTime: true,
                                ),
                                MetricCard(
                                  title: 'Last Update',
                                  icon: Icons.update_rounded,
                                  iconColor: Theme.of(context).colorScheme.primary,
                                  value: _lastSuccessfulUpdate?.toString().substring(11, 19) ?? "Never",
                                  subtitle: 'Updates Sent: $_locationUpdatesSent',
                                ),
                                _buildLocationCard(),
                                _buildSessionMonitoringCard(),
                                _buildMovementStatsCard(),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.all(context.responsiveFont(16.0)),
                          child: SizedBox(
                            width: double.infinity,
                            height: ResponsiveUIService.getResponsiveButtonHeight(
                              context: context,
                              baseHeight: 48.0,
                            ),
                            child: ElevatedButton.icon(
                              onPressed: _performLogout,
                              icon: Icon(Icons.logout),
                              label: AutoSizeText(
                                'Logout',
                                maxFontSize: getResponsiveFont(16.0),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
            if (!_isLocationServiceEnabled)
              Container(
                color: Colors.black.withOpacity(0.85),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.location_off,
                        color: Colors.white,
                        size: 80,
                      ),
                      SizedBox(height: 20),
                      Text(
                        'Location is required to continue',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20.0,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<String> _buildRealtimeConsoleLines() {
    if (_consoleLines.isEmpty) {
      _seedConsole();
    }
    return _consoleLines;
  }

  double _calculateAspectRatio() {
    final screenType = ResponsiveUIService.getScreenType(
      MediaQuery.of(context).size.width,
    );
    final orientation = MediaQuery.of(context).orientation;

    switch (screenType) {
      case ScreenType.mobile:
        return orientation == Orientation.landscape ? 1.6 : 1.3;
      case ScreenType.tablet:
        return orientation == Orientation.landscape ? 1.8 : 1.5;
      case ScreenType.desktop:
      case ScreenType.large:
        return orientation == Orientation.landscape ? 2.0 : 1.7;
    }
  }

  Widget _buildSessionMonitoringCard() {
    final lastCheckText = _lastSessionCheck != null
        ? _lastSessionCheck!.toString().substring(11, 19)
        : 'Never';

    final statusText = _sessionActive ? 'Active' : 'Lost';
    final failureText = _consecutiveSessionFailures > 0
        ? ' (${_consecutiveSessionFailures} failures)'
        : '';

    return MetricCard(
      title: 'Session Monitor',
      icon: _sessionActive ? Icons.verified_user : Icons.error,
      iconColor: _sessionActive ? Colors.green : Colors.red,
      value: statusText + failureText,
      subtitle: 'Last Check: $lastCheckText',
      isRealTime: true,
    );
  }

  // NEW: Movement statistics card showing adaptive update intervals
  Widget _buildMovementStatsCard() {
    final position = _locationService.currentPosition;
    
    if (position == null) {
      return MetricCard(
        title: 'Smart Updates',
        icon: Icons.speed,
        iconColor: Colors.grey,
        value: 'NO GPS',
        subtitle: 'Waiting for location...',
        isRealTime: true,
      );
    }
    
    final speed = position.speed;
    final kmh = (speed * 3.6).clamp(0.0, double.infinity);
    final nextInterval = _calculateOptimalUpdateInterval(position);
    
    String movementStatus;
    Color statusColor;
    
    if (speed >= 3.9) { // >14 km/h
      movementStatus = 'FAST';
      statusColor = Colors.red;
    } else if (speed >= 2.0) {
      movementStatus = 'MOVING';
      statusColor = Colors.orange;
    } else if (speed >= 1.0) {
      movementStatus = 'SLOW';
      statusColor = Colors.yellow[700]!;
    } else {
      movementStatus = 'STATIONARY';
      statusColor = Colors.green;
    }
    
    return MetricCard(
      title: 'Smart Updates',
      icon: Icons.speed,
      iconColor: statusColor,
      value: movementStatus,
      subtitle: 'Next: ${nextInterval.inSeconds}s • ${kmh.toInt()} km/h',
      isRealTime: true,
    );
  }

  Widget _buildLocationCard() {
    if (_isLocationLoading) {
      return Card(
        child: Center(
          child: SizedBox(
            width: context.responsiveFont(32.0),
            height: context.responsiveFont(32.0),
            child: CircularProgressIndicator(
              strokeWidth: context.responsiveFont(3.0),
            ),
          ),
        ),
      );
    }

    final position = _locationService.currentPosition;

    if (position == null) {
      return Card(
        child: InkWell(
          onTap: _refreshLocation,
          child: Container(
            padding: context.responsivePadding(),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.location_off,
                  size: ResponsiveUIService.getResponsiveIconSize(
                    context: context,
                    baseIconSize: 24.0,
                  ),
                  color: Colors.red,
                ),
                SizedBox(height: context.responsiveFont(4.0)),
                AutoSizeText(
                  'Location\nUnavailable',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold),
                  maxLines: 2,
                  maxFontSize: getResponsiveFont(12.0),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Removed unused local variable

    return MetricCard(
      title: 'Location',
      icon: Icons.gps_fixed_rounded,
      iconColor: Colors.green,
      value: 'Lat: ${position.latitude.toStringAsFixed(4)}\nLng: ${position.longitude.toStringAsFixed(4)}',
      subtitle: 'Acc: ±${position.accuracy.toStringAsFixed(1)}m',
      isRealTime: true,
      onTap: _refreshLocation,
    );
  }

  Future<void> _checkForUpdates() async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              SizedBox(width: 12),
              Text('Checking for updates...'),
            ],
          ),
          backgroundColor: Colors.blue[800],
          duration: Duration(seconds: 2),
        ),
      );

      final updateService = UpdateService();
      final result = await updateService.checkForUpdates();

      ScaffoldMessenger.of(context).clearSnackBars();

      if (result.hasUpdate && result.updateInfo != null) {
        showDialog(
          context: context,
          builder: (context) => UpdateDialog(
            updateInfo: result.updateInfo!,
            currentVersion: result.currentVersion,
          ),
        );
      } else if (result.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Update check failed: ${result.error}',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red[800],
            duration: Duration(seconds: 5),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text(
                  'You are using the latest version.',
                  style: TextStyle(fontSize: 14),
                ),
              ],
            ),
            backgroundColor: Colors.green[800],
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Update check failed: $e',
                  style: TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.red[800],
          duration: Duration(seconds: 5),
        ),
      );
    }
  }
}