import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter/material.dart';

class WakeLockService {
  static final WakeLockService _instance = WakeLockService._internal();
  factory WakeLockService() => _instance;
  WakeLockService._internal();

  bool _isWakeLockEnabled = false;
  bool _isInitialized = false;

  // Getters
  bool get isWakeLockEnabled => _isWakeLockEnabled;
  bool get isInitialized => _isInitialized;

  /// Initialize the wake lock service
  Future<void> initialize() async {
    try {
      _isInitialized = true;
      print('WakeLockService: Initialized successfully');
    } catch (e) {
      print('WakeLockService: Error during initialization: $e');
    }
  }

  /// Enable wake lock to keep screen awake and app running
  Future<bool> enableWakeLock() async {
    try {
      if (!_isInitialized) {
        await initialize();
      }

      // Check if wake lock is supported
      final isSupported = await WakelockPlus.enabled;
      print('WakeLockService: Wake lock supported: $isSupported');

      // Enable wake lock
      await WakelockPlus.enable();
      _isWakeLockEnabled = await WakelockPlus.enabled;
      
      print('WakeLockService: Wake lock enabled: $_isWakeLockEnabled');
      return _isWakeLockEnabled;
    } catch (e) {
      print('WakeLockService: Error enabling wake lock: $e');
      return false;
    }
  }

  /// Disable wake lock to allow normal power management
  Future<bool> disableWakeLock() async {
    try {
      await WakelockPlus.disable();
      _isWakeLockEnabled = await WakelockPlus.enabled;
      
      print('WakeLockService: Wake lock disabled: ${!_isWakeLockEnabled}');
      return !_isWakeLockEnabled;
    } catch (e) {
      print('WakeLockService: Error disabling wake lock: $e');
      return false;
    }
  }

  /// Toggle wake lock state
  Future<bool> toggleWakeLock() async {
    if (_isWakeLockEnabled) {
      return await disableWakeLock();
    } else {
      return await enableWakeLock();
    }
  }

  /// Check current wake lock status
  Future<bool> checkWakeLockStatus() async {
    try {
      _isWakeLockEnabled = await WakelockPlus.enabled;
      return _isWakeLockEnabled;
    } catch (e) {
      print('WakeLockService: Error checking wake lock status: $e');
      return false;
    }
  }

  /// Get wake lock status text for UI
  String getStatusText() {
    if (!_isInitialized) return 'Not Initialized';
    return _isWakeLockEnabled ? 'ACTIVE' : 'DISABLED';
  }

  /// Get wake lock status color for UI
  Color getStatusColor() {
    if (!_isInitialized) return Colors.grey;
    return _isWakeLockEnabled ? Colors.green : Colors.orange;
  }

  /// Get wake lock icon for UI
  IconData getStatusIcon() {
    if (!_isInitialized) return Icons.help_outline;
    return _isWakeLockEnabled ? Icons.screen_lock_rotation : Icons.screen_lock_portrait;
  }

  /// Force enable wake lock for critical operations
  Future<void> forceEnableForCriticalOperation() async {
    try {
      print('WakeLockService: Force enabling wake lock for critical operation...');
      await WakelockPlus.enable();
      _isWakeLockEnabled = true;
      print('WakeLockService: Critical operation wake lock enabled');
    } catch (e) {
      print('WakeLockService: Error force enabling wake lock: $e');
    }
  }

  /// Smart wake lock management based on app state
  Future<void> manageWakeLockForTracking(bool isTracking) async {
    if (isTracking) {
      print('WakeLockService: Enabling wake lock for active tracking...');
      await enableWakeLock();
    } else {
      print('WakeLockService: Disabling wake lock - tracking stopped...');
      await disableWakeLock();
    }
  }

  /// Clean up resources
  void dispose() {
    print('WakeLockService: Disposing...');
    disableWakeLock().catchError((e) {
      print('WakeLockService: Error during disposal: $e');
    });
  }

  /// Get detailed status information
  Map<String, dynamic> getDetailedStatus() {
    return {
      'isInitialized': _isInitialized,
      'isWakeLockEnabled': _isWakeLockEnabled,
      'statusText': getStatusText(),
      'canToggle': _isInitialized,
    };
  }
}