import 'dart:async';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WatchdogService {
  static final WatchdogService _instance = WatchdogService._internal();
  factory WatchdogService() => _instance;
  WatchdogService._internal();

  Timer? _heartbeatTimer;
  Timer? _watchdogTimer;
  DateTime? _lastHeartbeat;
  bool _isRunning = false;
  Function? _onAppDead;
  
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  // Initialize watchdog
  Future<void> initialize({Function? onAppDead}) async {
    _onAppDead = onAppDead;
    await _initializeNotifications();
    print('WatchdogService: Initialized');
  }

  // Initialize notifications
  Future<void> _initializeNotifications() async {
    try {
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );
      
      await _notifications.initialize(initSettings);
      print('WatchdogService: Notifications initialized');
    } catch (e) {
      print('WatchdogService: Error initializing notifications: $e');
    }
  }

  // Start watchdog monitoring
  void startWatchdog() {
    if (_isRunning) {
      print('WatchdogService: Already running');
      return;
    }

    _isRunning = true;
    _lastHeartbeat = DateTime.now();
    
    // Send heartbeat every 5 minutes
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      _sendHeartbeat();
    });

    // Check for dead app every minute
    _watchdogTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _checkAppHealth();
    });

    print('WatchdogService: Started monitoring');
  }

  // Stop watchdog
  void stopWatchdog() {
    _heartbeatTimer?.cancel();
    _watchdogTimer?.cancel();
    _isRunning = false;
    print('WatchdogService: Stopped monitoring');
  }

  // Send heartbeat signal
  void _sendHeartbeat() {
    _lastHeartbeat = DateTime.now();
    _saveHeartbeatToStorage();
    print('WatchdogService: Heartbeat sent at ${_lastHeartbeat!.hour}:${_lastHeartbeat!.minute}');
  }

  // Save heartbeat to persistent storage
  Future<void> _saveHeartbeatToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_heartbeat', _lastHeartbeat!.toIso8601String());
      await prefs.setBool('app_is_alive', true);
    } catch (e) {
      print('WatchdogService: Error saving heartbeat: $e');
    }
  }

  // Check app health
  void _checkAppHealth() {
    if (_lastHeartbeat == null) return;

    final now = DateTime.now();
    final timeSinceLastHeartbeat = now.difference(_lastHeartbeat!);
    
    // If no heartbeat for 15 minutes, consider app dead
    if (timeSinceLastHeartbeat.inMinutes >= 15) {
      print('WatchdogService: App appears to be dead! Last heartbeat: ${timeSinceLastHeartbeat.inMinutes} minutes ago');
      _handleAppDead();
    }
  }

  // Handle dead app
  void _handleAppDead() async {
    try {
      await _showAppDeadNotification();
      await _markAppAsDead();
      
      // Try to restart or notify callback
      if (_onAppDead != null) {
        _onAppDead!();
      }
      
    } catch (e) {
      print('WatchdogService: Error handling dead app: $e');
    }
  }

  // Show notification that app is dead
  Future<void> _showAppDeadNotification() async {
    try {
      const androidDetails = AndroidNotificationDetails(
        'watchdog_channel',
        'App Watchdog',
        channelDescription: 'Monitors app health',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notifications.show(
        999, // Unique ID for watchdog notifications
        'PNP Device Monitor Alert',
        'App monitoring stopped. Please reopen the app to continue tracking.',
        notificationDetails,
      );
      
      print('WatchdogService: Dead app notification sent');
    } catch (e) {
      print('WatchdogService: Error showing notification: $e');
    }
  }

  // Mark app as dead in storage
  Future<void> _markAppAsDead() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('app_is_alive', false);
      await prefs.setString('app_died_at', DateTime.now().toIso8601String());
    } catch (e) {
      print('WatchdogService: Error marking app as dead: $e');
    }
  }

  // Check if app was previously dead
  Future<bool> wasAppDead() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final wasAlive = prefs.getBool('app_is_alive') ?? true;
      return !wasAlive;
    } catch (e) {
      print('WatchdogService: Error checking if app was dead: $e');
      return false;
    }
  }

  // Mark app as alive (call this when app starts)
  Future<void> markAppAsAlive() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('app_is_alive', true);
      await prefs.setString('app_started_at', DateTime.now().toIso8601String());
      _lastHeartbeat = DateTime.now();
      print('WatchdogService: App marked as alive');
    } catch (e) {
      print('WatchdogService: Error marking app as alive: $e');
    }
  }

  // Get watchdog status
  Map<String, dynamic> getStatus() {
    return {
      'isRunning': _isRunning,
      'lastHeartbeat': _lastHeartbeat?.toIso8601String(),
      'minutesSinceLastHeartbeat': _lastHeartbeat != null 
        ? DateTime.now().difference(_lastHeartbeat!).inMinutes 
        : null,
    };
  }

  // Force heartbeat (call this from main app periodically)
  void ping() {
    _sendHeartbeat();
  }

  void dispose() {
    stopWatchdog();
  }
}