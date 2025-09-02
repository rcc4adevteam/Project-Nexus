import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'api_service.dart';
import '../utils/constants.dart';

class DeviceService {
  static final DeviceService _instance = DeviceService._internal();
  factory DeviceService() => _instance;
  DeviceService._internal();

  final Battery _battery = Battery();
  final Connectivity _connectivity = Connectivity();
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  StreamSubscription<BatteryState>? _batterySubscription;
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  
  // Timer for the repeating offline notification
  Timer? _offlineNotificationTimer;
  Timer? _batteryUpdateTimer;

  int _batteryLevel = 0;
  BatteryState _batteryState = BatteryState.unknown;
  ConnectivityResult _connectivityResult = ConnectivityResult.none;
  String _signalStatus = SignalStatus.poor; // UPDATED: Changed variable name and default value
  bool _isOnline = true;
  bool _wasOfflineNotificationSent = false;
  Timer? _signalUpdateTimer;

  int get batteryLevel => _batteryLevel;
  BatteryState get batteryState => _batteryState;
  ConnectivityResult get connectivityResult => _connectivityResult;
  String get signalStatus => _signalStatus; // UPDATED: Changed getter name
  bool get isOnline => _isOnline;

  Future<void> initialize() async {
    print('DeviceService: Initializing...');
    await _updateBatteryInfo();
    await _updateConnectivityInfo();
    await _initializeNotifications(); 
    _startListening();
    _startBatteryMonitoring();
    _startSignalMonitoring(); // UPDATED: Start API-based signal monitoring
    
    // NEW: Trigger immediate connectivity update to ensure webapp shows correct status
    await _triggerImmediateConnectivityUpdate();
    
    print('DeviceService: Initialization complete');
  }

  // NEW: Trigger immediate connectivity update for instant webapp status
  Future<void> _triggerImmediateConnectivityUpdate() async {
    try {
      print('DeviceService: Triggering immediate connectivity update...');
      
      // Force immediate connectivity check
      await _updateConnectivityInfo();
      
      // If online, trigger immediate location update to show online status
      if (_isOnline) {
        print('DeviceService: Device is online, triggering immediate status update');
        // This will be handled by the dashboard to send immediate location update
      } else {
        print('DeviceService: Device is offline, webapp will show offline status');
      }
    } catch (e) {
      print('DeviceService: Error in immediate connectivity update: $e');
    }
  }

  Future<void> _initializeNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    await _notifications.initialize(initializationSettings);
  }

  // Enhanced offline notification that persists on lock screen
  Future<void> _showConnectionLostNotification() async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'connectivity_channel',
      'Connectivity Status',
      channelDescription: 'Notifications for network connectivity changes',
      importance: Importance.max,
      priority: Priority.high,
      sound: RawResourceAndroidNotificationSound('alarm_sound'),
      enableVibration: true,
      visibility: NotificationVisibility.public,
      ongoing: true,
      showWhen: true,
      autoCancel: false,
      fullScreenIntent: true,
    );
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);
    await _notifications.show(
      100,
      'Network Connection Lost',
      'Device is offline. Location tracking continues but cannot send data. Auto-reconnect enabled.',
      platformChannelSpecifics,
    );
    _wasOfflineNotificationSent = true;
  }

  // Connection restored notification
  Future<void> _showConnectionRestoredNotification() async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'connectivity_channel',
      'Connectivity Status',
      channelDescription: 'Notifications for network connectivity changes',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: false,
      visibility: NotificationVisibility.public,
      autoCancel: true,
    );
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);
    await _notifications.show(
      102,
      'Connection Restored',
      'Network connection restored. Location tracking resumed successfully.',
      platformChannelSpecifics,
    );
    
    // Auto-dismiss after 3 seconds
    Timer(const Duration(seconds: 3), () {
      _notifications.cancel(102);
    });
  }

  // Enhanced low battery notification for lock screen
  Future<void> _showLowBatteryNotification() async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'battery_alerts',
      'Battery Alerts',
      channelDescription: 'Notifications for critical battery levels',
      importance: Importance.max,
      priority: Priority.high,
      sound: RawResourceAndroidNotificationSound('alarm_sound'),
      enableVibration: true,
      visibility: NotificationVisibility.public,
      ongoing: false,
      showWhen: true,
      fullScreenIntent: true,
    );
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);
    await _notifications.show(
      101,
      'Critical Battery Level',
      'Battery at $_batteryLevel%. Connect charger immediately to ensure continuous tracking.',
      platformChannelSpecifics,
    );
  }

  void _startListening() {
    // Battery state monitoring
    _batterySubscription = _battery.onBatteryStateChanged.listen((state) {
      _batteryState = state;
      print('DeviceService: Battery state changed to $state');
    });

    // Enhanced connectivity monitoring with automatic reconnection
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((result) {
      final wasOnline = _isOnline;
      _connectivityResult = result;
      _isOnline = result != ConnectivityResult.none;

      print('DeviceService: Connectivity changed to $result (${_isOnline ? "online" : "offline"})');

      if (!_isOnline && wasOnline) {
        // Connection lost
        _signalStatus = SignalStatus.poor; // UPDATED: Use constant
        _handleConnectionLost();
      } else if (_isOnline && !wasOnline) {
        // Connection restored - AUTOMATIC RECONNECTION
        _handleConnectionRestored();
        // Trigger immediate signal update when connection is restored
        _updateSignalStatus(); // UPDATED: Changed method name
      }
    });
  }

  // Handle connection lost
  void _handleConnectionLost() {
    print('DeviceService: Connection lost, starting persistent notifications');
    _offlineNotificationTimer?.cancel();
    _offlineNotificationTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _showConnectionLostNotification();
    });
    _showConnectionLostNotification();
  }

  // Handle connection restored with automatic reconnection
  void _handleConnectionRestored() {
    print('DeviceService: Connection restored, handling auto-reconnection');
    _offlineNotificationTimer?.cancel();
    
    if (_wasOfflineNotificationSent) {
      _notifications.cancel(100);
      _showConnectionRestoredNotification();
      _wasOfflineNotificationSent = false;
    }
    
    print('DeviceService: Auto-reconnection notification sent');
  }

  void _startBatteryMonitoring() {
    // Update battery level every 30 seconds
    _batteryUpdateTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      await _updateBatteryInfo();
      
      // Show critical battery warning with enhanced notification
      if (_batteryLevel <= 15 && _batteryState != BatteryState.charging) {
        _showLowBatteryNotification();
      }
    });
  }

  Future<void> _updateBatteryInfo() async {
    try {
      final newLevel = await _battery.batteryLevel;
      final newState = await _battery.batteryState;
      
      if (newLevel != _batteryLevel || newState != _batteryState) {
        _batteryLevel = newLevel;
        _batteryState = newState;
        print('DeviceService: Battery updated - Level: $_batteryLevel%, State: $_batteryState');
      }
    } catch (e) {
      print('DeviceService: Error updating battery info: $e');
    }
  }

  Future<void> _updateConnectivityInfo() async {
    try {
      _connectivityResult = await _connectivity.checkConnectivity();
      _isOnline = _connectivityResult != ConnectivityResult.none;
      print('DeviceService: Connectivity updated - Result: $_connectivityResult, Online: $_isOnline');
      
      // Update signal status using API-based detection
      if (_isOnline) {
        await _updateSignalStatus(); // UPDATED: Changed method name
      } else {
        _signalStatus = SignalStatus.poor; // UPDATED: Use constant
      }
    } catch (e) {
      print('DeviceService: Error updating connectivity info: $e');
    }
  }

  // UPDATED: Start API-based signal monitoring
  void _startSignalMonitoring() {
    // Update signal status every 30 seconds
    _signalUpdateTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (_isOnline) {
        await _updateSignalStatus(); // UPDATED: Changed method name
      }
    });
  }

  // UPDATED: Update signal status using API service
  Future<void> _updateSignalStatus() async {
    try {
      final newSignalStatus = await ApiService.getSignalStatus(); // UPDATED: Changed method name
      if (newSignalStatus != _signalStatus) {
        _signalStatus = newSignalStatus;
        print('DeviceService: Signal status updated to $_signalStatus'); // UPDATED: Changed log message
      }
    } catch (e) {
      print('DeviceService: Error updating signal status: $e'); // UPDATED: Changed log message
      _signalStatus = SignalStatus.poor; // UPDATED: Use constant
    }
  }

  // Get detailed device status
  Map<String, dynamic> getDeviceStatus() {
    return {
      'batteryLevel': _batteryLevel,
      'batteryState': _batteryState.toString().split('.').last,
      'isCharging': _batteryState == BatteryState.charging,
      'connectivity': _connectivityResult.toString().split('.').last,
      'signalStatus': _signalStatus, // UPDATED: Changed key name
      'isOnline': _isOnline,
      'lastUpdated': DateTime.now().toIso8601String(),
    };
  }

  // Get battery health status
  String getBatteryHealthStatus() {
    if (_batteryState == BatteryState.charging) {
      return 'Charging (${_batteryLevel}%)';
    } else if (_batteryLevel > 50) {
      return 'Good (${_batteryLevel}%)';
    } else if (_batteryLevel > 20) {
      return 'Low (${_batteryLevel}%)';
    } else {
      return 'Critical (${_batteryLevel}%)';
    }
  }

  // Get connectivity status description
  String getConnectivityDescription() {
    if (!_isOnline) return 'Offline - Auto-reconnect enabled';
    
    switch (_connectivityResult) {
      case ConnectivityResult.wifi:
        return 'WiFi - Strong signal';
      case ConnectivityResult.mobile:
        return 'Mobile Data - Good signal';
      case ConnectivityResult.ethernet:
        return 'Ethernet - Stable connection';
      case ConnectivityResult.bluetooth:
        return 'Bluetooth - Limited connection';
      default:
        return 'Unknown connection type';
    }
  }

  // Force refresh all device info - enhanced for pull-to-refresh
  Future<void> refreshDeviceInfo() async {
    print('DeviceService: Force refreshing device info...');
    try {
      await Future.wait([
        _updateBatteryInfo(),
        _updateConnectivityInfo(),
      ], eagerError: false);
      
      print('DeviceService: Force refresh completed successfully');
    } catch (e) {
      print('DeviceService: Error during force refresh: $e');
      throw e;
    }
  }

  void dispose() {
    print('DeviceService: Disposing...');
    _batterySubscription?.cancel();
    _connectivitySubscription?.cancel();
    _offlineNotificationTimer?.cancel();
    _batteryUpdateTimer?.cancel();
    _signalUpdateTimer?.cancel(); // UPDATED: Cancel signal timer
  }
}