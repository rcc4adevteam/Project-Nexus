import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../utils/constants.dart';
import 'secure_storage_service.dart';
import 'error_handling_service.dart';
import 'loading_service.dart';

class ApiService {
  // ===== BASIC API METHODS =====
  
  static Future<ApiResponse> login(String token, String deploymentCode) async {
    final url = Uri.parse('${AppConstants.baseUrl}setUnit');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    final body = json.encode({
      'deploymentCode': deploymentCode,
      'action': 'login',
      'timestamp': DateTime.now().toIso8601String(),
      'deviceInfo': await _getDeviceInfo(),
    });

    try {
      final response = await http.post(url, headers: headers, body: body);
      return ApiResponse.fromResponse(response);
    } catch (e) {
      return ApiResponse.error(ErrorHandlingService.getUserFriendlyError(e));
    }
  }

  static Future<ApiResponse> logout(String token, String deploymentCode) async {
    final url = Uri.parse('${AppConstants.baseUrl}setUnit');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    final body = json.encode({
      'deploymentCode': deploymentCode,
      'action': 'logout',
      'timestamp': DateTime.now().toIso8601String(),
    });

    try {
      final response = await http.post(url, headers: headers, body: body);
      return ApiResponse.fromResponse(response);
    } catch (e) {
      return ApiResponse.error(ErrorHandlingService.getUserFriendlyError(e));
    }
  }

  static Future<ApiResponse> checkStatus(String token, String deploymentCode) async {
    final url = Uri.parse('${AppConstants.baseUrl}checkStatus');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    final body = json.encode({
      'deploymentCode': deploymentCode,
      'timestamp': DateTime.now().toIso8601String(),
    });

    try {
      final response = await http.post(
        url, 
        headers: headers, 
        body: body,
      ).timeout(const Duration(seconds: 8));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return ApiResponse(
          success: true,
          message: 'Status checked successfully',
          data: data,
        );
      } else if (response.statusCode == 401) {
        return ApiResponse(
          success: false,
          message: 'Authentication failed - token may be invalid',
          data: {'isLoggedIn': false},
        );
      } else {
        return ApiResponse(
          success: false,
          message: 'Server error checking status',
          data: {'isLoggedIn': false},
        );
      }
    } on TimeoutException {
      return ApiResponse.error('Session check timed out');
    } catch (e) {
      return ApiResponse.error('Network error checking status: ${e.toString()}');
    }
  }

  // ===== LOCATION UPDATE METHODS =====
  
  // Basic location update
  static Future<ApiResponse> updateLocation({
    required String token,
    required String deploymentCode,
    required Position position,
    required int batteryLevel,
    required String signal,
    bool isAggressiveSync = false,
  }) async {
    final url = Uri.parse('${AppConstants.baseUrl}updateLocation');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
      'X-Sync-Type': isAggressiveSync ? 'aggressive' : 'normal',
    };
    
    final body = json.encode({
      'deploymentCode': deploymentCode,
      'location': {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'altitude': position.altitude,
        'speed': position.speed,
        'heading': position.heading,
      },
      'batteryStatus': batteryLevel,
      'signal': signal,
      'timestamp': DateTime.now().toIso8601String(),
      'syncType': isAggressiveSync ? 'aggressive' : 'normal',
      'deviceInfo': isAggressiveSync ? await _getDeviceInfo() : null,
    });

    try {
      final response = await http.post(
        url, 
        headers: headers, 
        body: body
      ).timeout(Duration(seconds: isAggressiveSync ? 15 : 10));
      
      if (response.statusCode == 403) {
        return ApiResponse.error('Session expired. Please login again.');
      }
      
      final apiResponse = ApiResponse.fromResponse(response);
      
      if (apiResponse.success && isAggressiveSync) {
        print('ApiService: ✅ SYNC successful - device should show ONLINE');
      }
      
      return apiResponse;
    } catch (e) {
      return ApiResponse.error('Network error updating location: ${e.toString()}');
    }
  }

  // ===== OPTIMIZED LOCATION UPDATE METHODS =====
  
  // Movement-based cache to avoid duplicate sends
  static Position? _lastSentPosition;
  static int _lastSentBattery = -1;
  static String _lastSentSignal = '';
  static DateTime? _lastUpdateTime;
  static Timer? _adaptiveTimer;
  static Duration _currentInterval = Duration(seconds: 30);
  
  // Movement thresholds for adaptive updates
  static const double stationarySpeed = 1.0; // m/s (~3.6 km/h)
  static const double movingSpeed = 2.0; // m/s (~7.2 km/h)
  static const double fastMovingSpeed = 8.0; // m/s (~28.8 km/h)
  static const double movementDistance = 10.0; // meters
  
  // Adaptive update intervals based on movement and context
  static const Duration fastMovingInterval = Duration(seconds: 5);   // Fast movement
  static const Duration movingInterval = Duration(seconds: 15);       // Normal movement
  static const Duration slowMovingInterval = Duration(seconds: 30);  // Slow movement
  static const Duration stationaryInterval = Duration(minutes: 2);    // Stationary
  static const Duration lowBatteryInterval = Duration(minutes: 5);   // Low battery + stationary

  // Optimized location update with intelligent filtering
  static Future<ApiResponse> updateLocationOptimized({
    required String token,
    required String deploymentCode,
    required Position position,
    required int batteryLevel,
    required String signal,
    bool forceUpdate = false,
  }) async {
    
    // SMART FILTERING: Skip if no significant change
    if (!forceUpdate && _shouldSkipUpdate(position, batteryLevel, signal)) {
      print('⏭️ Skipped - no significant change');
      return ApiResponse(success: true, message: 'Skipped - no significant change');
    }
    
    // BUILD COMPRESSED PAYLOAD
    final compressedData = _buildCompressedPayload(
      deploymentCode: deploymentCode,
      position: position,
      batteryLevel: batteryLevel,
      signal: signal,
    );
    
    final url = Uri.parse('${AppConstants.baseUrl}updateLocation');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
      'X-Update-Type': 'optimized',
    };
    
    try {
      final response = await http.post(
        url,
        headers: headers,
        body: json.encode(compressedData),
      ).timeout(Duration(seconds: 8));
      
      // Update cache on successful send
      if (response.statusCode == 200) {
        _lastSentPosition = position;
        _lastSentBattery = batteryLevel;
        _lastSentSignal = signal;
        _lastUpdateTime = DateTime.now();
        
        final speed = position.speed * 3.6; // km/h
        print('✅ Location sent (${speed.toInt()} km/h) - Next: ${_currentInterval.inSeconds}s');
      }
      
      return ApiResponse.fromResponse(response);
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }

  // Check if update should be skipped to save data
  static bool _shouldSkipUpdate(Position position, int batteryLevel, String signal) {
    if (_lastSentPosition == null || _lastUpdateTime == null) return false;
    
    // Calculate distance moved
    final distance = Geolocator.distanceBetween(
      _lastSentPosition!.latitude,
      _lastSentPosition!.longitude,
      position.latitude,
      position.longitude,
    );
    
    // Check time since last update
    final timeSinceUpdate = DateTime.now().difference(_lastUpdateTime!);
    
    // NEVER skip if moving significantly
    if (distance >= movementDistance) return false;
    
    // NEVER skip if speed is high (moving fast)
    if (position.speed >= movingSpeed) return false;
    
    // Skip if stationary and other data unchanged and recent update
    if (distance < 5 && // Less than 5m movement
        batteryLevel == _lastSentBattery &&
        signal == _lastSentSignal &&
        timeSinceUpdate < Duration(minutes: 1)) {
      return true;
    }
    
    return false;
  }
  
  // Build compressed payload with minimal data
  static Map<String, dynamic> _buildCompressedPayload({
    required String deploymentCode,
    required Position position,
    required int batteryLevel,
    required String signal,
  }) {
    final data = <String, dynamic>{
      'deploymentCode': deploymentCode,
      'location': {
        'latitude': _roundCoordinate(position.latitude),
        'longitude': _roundCoordinate(position.longitude),
        'accuracy': position.accuracy.round(),
        'speed': _roundSpeed(position.speed),
        'altitude': position.altitude,
        'heading': position.heading,
      },
      'timestamp': DateTime.now().toIso8601String(),
    };
    
    // Only include battery if changed significantly
    if ((batteryLevel - _lastSentBattery).abs() >= 5 || _lastSentBattery == -1) {
      data['batteryStatus'] = batteryLevel;
    }
    
    // Only include signal if changed
    if (signal != _lastSentSignal || _lastSentSignal.isEmpty) {
      data['signal'] = signal;
    }
    
    // Include movement context for server optimization
    data['movementType'] = _getMovementType(position);
    
    return data;
  }
  
  // Round coordinates to reduce data size while maintaining accuracy
  static double _roundCoordinate(double coordinate) {
    return double.parse(coordinate.toStringAsFixed(5)); // ~1 meter precision
  }
  
  // Round speed to reduce data size
  static double _roundSpeed(double speed) {
    return double.parse(speed.toStringAsFixed(1)); // 0.1 m/s precision
  }
  
  // Get movement type for server context
  static String _getMovementType(Position position) {
    final speed = position.speed;
    
    if (speed >= fastMovingSpeed) return 'fast';
    if (speed >= movingSpeed) return 'moving';
    if (speed >= stationarySpeed) return 'slow';
    return 'stationary';
  }

  // ===== ADAPTIVE UPDATE SYSTEM =====
  
  // Start adaptive location updates with movement-based intervals
  static void startAdaptiveLocationUpdates({
    required String token,
    required String deploymentCode,
    required Function() getCurrentPosition,
    required Function() getBatteryLevel,
    required Function() getSignalStatus,
  }) {
    print('🚀 Starting MOVEMENT-BASED adaptive updates...');
    
    _adaptiveTimer?.cancel();
    _scheduleNextUpdate(
      token: token,
      deploymentCode: deploymentCode,
      getCurrentPosition: getCurrentPosition,
      getBatteryLevel: getBatteryLevel,
      getSignalStatus: getSignalStatus,
    );
  }
  
  static void _scheduleNextUpdate({
    required String token,
    required String deploymentCode,
    required Function() getCurrentPosition,
    required Function() getBatteryLevel,
    required Function() getSignalStatus,
  }) {
    _adaptiveTimer = Timer(_currentInterval, () async {
      await _processAdaptiveUpdate(
        token: token,
        deploymentCode: deploymentCode,
        getCurrentPosition: getCurrentPosition,
        getBatteryLevel: getBatteryLevel,
        getSignalStatus: getSignalStatus,
      );
      
      // Schedule next update with potentially new interval
      _scheduleNextUpdate(
        token: token,
        deploymentCode: deploymentCode,
        getCurrentPosition: getCurrentPosition,
        getBatteryLevel: getBatteryLevel,
        getSignalStatus: getSignalStatus,
      );
    });
  }
  
  static Future<void> _processAdaptiveUpdate({
    required String token,
    required String deploymentCode,
    required Function() getCurrentPosition,
    required Function() getBatteryLevel,
    required Function() getSignalStatus,
  }) async {
    try {
      final position = getCurrentPosition() as Position?;
      if (position == null) {
        print('📍 No position available, keeping current interval');
        return;
      }
      
      final batteryLevel = getBatteryLevel() as int;
      final signalStatus = getSignalStatus() as String;
      
      // Check if update is needed and send
      final updateResult = await updateLocationOptimized(
        token: token,
        deploymentCode: deploymentCode,
        position: position,
        batteryLevel: batteryLevel,
        signal: signalStatus,
      );
      
      if (updateResult.success) {
        // Calculate next interval based on current movement
        _currentInterval = _calculateOptimalInterval(position, batteryLevel);
        print('📊 Next update in: ${_currentInterval.inSeconds}s (${_getMovementStatus(position)})');
      }
      
    } catch (e) {
      print('❌ Adaptive update failed: $e');
    }
  }
  
  // Calculate optimal interval based on movement and battery
  static Duration _calculateOptimalInterval(Position position, int batteryLevel) {
    final speed = position.speed; // m/s
    
    // FAST MOVEMENT: 5 seconds (when device is moving fast)
    if (speed >= fastMovingSpeed) {
      return fastMovingInterval;
    }
    
    // NORMAL MOVEMENT: 15 seconds
    if (speed >= movingSpeed) {
      return movingInterval;
    }
    
    // SLOW MOVEMENT: 30 seconds
    if (speed >= stationarySpeed) {
      return slowMovingInterval;
    }
    
    // STATIONARY with low battery: 5 minutes
    if (batteryLevel < 20) {
      return lowBatteryInterval;
    }
    
    // STATIONARY with good battery: 2 minutes
    return stationaryInterval;
  }
  
  // Get movement status for logging
  static String _getMovementStatus(Position position) {
    final speed = position.speed;
    final kmh = speed * 3.6;
    
    if (speed >= fastMovingSpeed) return 'FAST (${kmh.toInt()} km/h)';
    if (speed >= movingSpeed) return 'MOVING (${kmh.toInt()} km/h)';
    if (speed >= stationarySpeed) return 'SLOW (${kmh.toInt()} km/h)';
    return 'STATIONARY (${kmh.toInt()} km/h)';
  }

  // Stop adaptive updates
  static void stopAdaptiveUpdates() {
    _adaptiveTimer?.cancel();
    _adaptiveTimer = null;
    print('🛑 Adaptive updates stopped');
  }
  
  // Get current update interval for UI display
  static Duration getCurrentInterval() => _currentInterval;
  
  // Get movement statistics for debugging
  static Map<String, dynamic> getMovementStats(Position? position) {
    if (position == null) return {'status': 'No position'};
    
    final speed = position.speed;
    final kmh = speed * 3.6;
    final movementType = _getMovementType(position);
    final nextInterval = _calculateOptimalInterval(position, 100);
    
    return {
      'speed_ms': speed.toStringAsFixed(1),
      'speed_kmh': kmh.toStringAsFixed(1),
      'movement_type': movementType,
      'current_interval': '${_currentInterval.inSeconds}s',
      'next_interval': '${nextInterval.inSeconds}s',
      'last_update': _lastUpdateTime?.toString().substring(11, 19) ?? 'Never',
    };
  }

  // ===== AGGRESSIVE SYNC METHODS =====
  
  // Send multiple aggressive sync updates
  static Future<List<ApiResponse>> sendAggressiveSyncBurst({
    required String token,
    required String deploymentCode,
    required Position position,
    int burstCount = 3,
  }) async {
    print('ApiService: Starting aggressive sync burst ($burstCount updates)...');
    
    List<ApiResponse> results = [];
    
    try {
      final batteryLevel = await _getBatteryLevel();
      final signal = await getSignalStatus();
      
      for (int i = 0; i < burstCount; i++) {
        print('ApiService: Sending sync ${i + 1}/$burstCount...');
        
        final response = await updateLocation(
          token: token,
          deploymentCode: deploymentCode,
          position: position,
          batteryLevel: batteryLevel,
          signal: signal,
          isAggressiveSync: true,
        );
        
        results.add(response);
        
        print('ApiService: sync ${i + 1}/$burstCount: ${response.success ? "✅ SUCCESS" : "❌ FAILED"}');
        
        if (i < burstCount - 1) {
          await Future.delayed(Duration(milliseconds: 500));
        }
      }
      
      final successCount = results.where((r) => r.success).length;
      print('ApiService: sync burst completed - $successCount/$burstCount successful');
      
    } catch (e) {
      print('ApiService: Error in sync burst: $e');
      results.add(ApiResponse.error('sync burst failed: $e'));
    }
    
    return results;
  }

  // Send immediate online status update
  static Future<ApiResponse> sendImmediateOnlineStatus({
    required String token,
    required String deploymentCode,
    Position? position,
  }) async {
    print('ApiService: Sending immediate online status update...');
    
    try {
      Position? currentPosition = position;
      
      if (currentPosition == null) {
        try {
          currentPosition = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 5),
          );
        } catch (e) {
          print('ApiService: Could not get quick location for online status: $e');
        }
      }
      
      if (currentPosition != null) {
        final batteryLevel = await _getBatteryLevel();
        final signal = await getSignalStatus();
        
        return await updateLocation(
          token: token,
          deploymentCode: deploymentCode,
          position: currentPosition,
          batteryLevel: batteryLevel,
          signal: signal,
          isAggressiveSync: true,
        );
      } else {
        return await _sendHeartbeatUpdate(token, deploymentCode);
      }
      
    } catch (e) {
      print('ApiService: Error sending immediate online status: $e');
      return ApiResponse.error('Failed to send online status: $e');
    }
  }

  // Send heartbeat update without location
  static Future<ApiResponse> _sendHeartbeatUpdate(String token, String deploymentCode) async {
    final url = Uri.parse('${AppConstants.baseUrl}heartbeat');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    final body = json.encode({
      'deploymentCode': deploymentCode,
      'status': 'online',
      'timestamp': DateTime.now().toIso8601String(),
      'batteryStatus': await _getBatteryLevel(),
      'signal': await getSignalStatus(),
    });

    try {
      final response = await http.post(url, headers: headers, body: body);
      return ApiResponse.fromResponse(response);
    } catch (e) {
      return ApiResponse.error('Heartbeat update failed: ${e.toString()}');
    }
  }

  // ===== SIGNAL STATUS DETECTION =====
  
  // Get signal status based on API specification
  static Future<String> getSignalStatus() async {
    try {
      // Test actual API performance to determine real signal quality
      final connectivity = Connectivity();
      final result = await connectivity.checkConnectivity();
      
      // If no connectivity, return poor
      if (result == ConnectivityResult.none) {
        return SignalStatus.poor;
      }
      
      // Test actual network performance with API endpoint
      final performanceScore = await _testNetworkPerformance();
      
      // Determine signal status based on actual performance and API specification
      // API expects: "strong", "weak", "poor", etc.
      if (performanceScore >= 60) {
        return SignalStatus.strong;  // API compatible: combines strong and moderate
      } else if (performanceScore >= 30) {
        return SignalStatus.weak;    // API compatible
      } else {
        return SignalStatus.poor;    // API compatible
      }
    } catch (e) {
      print('ApiService: Error getting signal status: $e');
      return SignalStatus.poor;
    }
  }

  // Test actual network performance with API
  static Future<int> _testNetworkPerformance() async {
    try {
      final stopwatch = Stopwatch()..start();
      
      // Make a lightweight request to test API response time
      final url = Uri.parse('${AppConstants.baseUrl}checkStatus');
      final headers = {'Content-Type': 'application/json'};
      
      final response = await http.post(
        url,
        headers: headers,
        body: '{"test": "ping"}',
      ).timeout(const Duration(seconds: 3));
      
      stopwatch.stop();
      final responseTime = stopwatch.elapsedMilliseconds;
      
      // Calculate performance score based on response time and status
      int score = 0;
      
      // Response time scoring (0-50 points)
      if (responseTime <= 500) {
        score += 50; // Excellent response time
      } else if (responseTime <= 1000) {
        score += 40; // Good response time
      } else if (responseTime <= 2000) {
        score += 25; // Fair response time
      } else {
        score += 10; // Poor response time
      }
      
      // HTTP status scoring (0-50 points)
      if (response.statusCode >= 200 && response.statusCode < 300) {
        score += 50; // Success response
      } else if (response.statusCode >= 400 && response.statusCode < 500) {
        score += 25; // Client error but server reachable
      } else {
        score += 10; // Server error
      }
      
      print('ApiService: Network performance test - Response time: ${responseTime}ms, Status: ${response.statusCode}, Score: $score');
      
      return score;
    } catch (e) {
      print('ApiService: Network performance test failed: $e');
      return 0; // No connectivity or severe issues
    }
  }

  // ===== HELPER METHODS =====
  
  // Helper methods for device information
  static Future<String> _getDeviceInfo() async {
    try {
      return 'Mobile Device - ${DateTime.now().toIso8601String()}';
    } catch (e) {
      return 'Unknown Device';
    }
  }

  static Future<int> _getBatteryLevel() async {
    try {
      final battery = Battery();
      return await battery.batteryLevel;
    } catch (e) {
      return 100; // Default value
    }
  }
}

// Updated API Response class
class ApiResponse {
  final bool success;
  final String message;
  final Map<String, dynamic>? data;

  ApiResponse({
    required this.success,
    required this.message,
    this.data,
  });

  factory ApiResponse.fromResponse(http.Response response) {
    try {
      final body = json.decode(response.body);
      return ApiResponse(
        success: response.statusCode == 200 && (body['success'] ?? false),
        message: body['message'] ?? 'Request completed',
        data: body,
      );
    } catch (e) {
      return ApiResponse(
        success: false,
        message: 'Invalid response format from server',
      );
    }
  }

  factory ApiResponse.error(String message) {
    return ApiResponse(success: false, message: message);
  }
}