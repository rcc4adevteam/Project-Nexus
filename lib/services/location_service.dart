import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as permission_handler;
import 'package:battery_plus/battery_plus.dart'; // ✅ NEW IMPORT ADDED
import 'dart:async';
import '../utils/constants.dart'; // UPDATED: Added import for signal status constants

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  StreamSubscription<Position>? _positionSubscription;
  Position? _currentPosition;
  bool _isLocationEnabled = false;
  bool _hasLocationPermission = false;
  bool _hasBackgroundLocationPermission = false;
  bool _isInitializing = false;
  
  // ✅ NEW: Smart filtering variables for Phase 2 optimization
  Position? _lastSentPosition; // Track last position sent to server
  DateTime? _lastUpdateTime;
  bool _isDeviceMoving = false;
  double _lastSpeed = 0.0;
  int _batteryLevel = 100;
  Timer? _batteryCheckTimer;
  final Battery _battery = Battery(); // ✅ NEW: Battery instance
  
  // Callbacks for location updates
  Function(Position)? _onLocationUpdate;

  // Getters
  Position? get currentPosition => _currentPosition;
  bool get isLocationEnabled => _isLocationEnabled;
  bool get hasLocationPermission => _hasLocationPermission;
  bool get hasBackgroundLocationPermission => _hasBackgroundLocationPermission;
  
  // ✅ NEW: Smart filtering getters for Phase 2
  bool get shouldSendUpdate => _shouldSendLocationUpdate();
  int get batteryLevel => _batteryLevel; // ✅ NEW: Expose battery level

  // ✅ NEW: Initialize battery monitoring for smart filtering
  Future<void> _initializeBatteryMonitoring() async {
    try {
      _batteryLevel = await _battery.batteryLevel;
      print('LocationService: Initial battery level: $_batteryLevel%');
      
      // Start periodic battery level checks every 30 seconds
      _batteryCheckTimer?.cancel();
      _batteryCheckTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
        try {
          final newBatteryLevel = await _battery.batteryLevel;
          if (newBatteryLevel != _batteryLevel) {
            _batteryLevel = newBatteryLevel;
            print('LocationService: Battery level updated to $_batteryLevel%');
          }
        } catch (e) {
          print('LocationService: Error checking battery level: $e');
        }
      });
    } catch (e) {
      print('LocationService: Error initializing battery monitoring: $e');
      _batteryLevel = 100; // Default to full battery if we can't read it
    }
  }

  // ✅ NEW: Smart filtering logic for Phase 2
  bool _shouldSendLocationUpdate() {
    if (_currentPosition == null) {
      print('LocationService: No current position available');
      return false;
    }
    
    final now = DateTime.now();
    final minInterval = _getMinUpdateInterval();
    
    // Always send first position
    if (_lastSentPosition == null || _lastUpdateTime == null) {
      print('LocationService: First position - should send');
      return true;
    }
    
    // Check minimum time interval
    if (now.difference(_lastUpdateTime!).inSeconds < minInterval) {
      print('LocationService: Too soon since last update (${now.difference(_lastUpdateTime!).inSeconds}s < ${minInterval}s)');
      return false;
    }
    
    // Calculate distance from last sent position
    final distanceFromLast = Geolocator.distanceBetween(
      _lastSentPosition!.latitude,
      _lastSentPosition!.longitude,
      _currentPosition!.latitude,
      _currentPosition!.longitude,
    );
    
    // Update movement status based on speed
    _lastSpeed = _currentPosition!.speed;
    _isDeviceMoving = _lastSpeed > 1.0; // Consider moving if speed > 1 m/s (3.6 km/h)
    
    // Dynamic distance threshold based on movement and battery
    double distanceThreshold = 10.0; // Base threshold in meters
    
    if (_isDeviceMoving) {
      // Moving device - more frequent updates
      distanceThreshold = 5.0;
    } else {
      // Stationary device - less frequent updates
      distanceThreshold = 20.0;
    }
    
    // Apply battery multiplier
    distanceThreshold *= _getBatteryMultiplier();
    
    final shouldSend = distanceFromLast >= distanceThreshold;
    
    print('LocationService: Distance from last: ${distanceFromLast.toStringAsFixed(1)}m, '
          'Threshold: ${distanceThreshold.toStringAsFixed(1)}m, '
          'Moving: $_isDeviceMoving, '
          'Speed: ${_lastSpeed.toStringAsFixed(1)}m/s, '
          'Battery: $_batteryLevel%, '
          'Should send: $shouldSend');
    
    return shouldSend;
  }

  // ✅ NEW: Battery-aware multiplier for Phase 2
  double _getBatteryMultiplier() {
    if (_batteryLevel >= 50) {
      return 1.0; // Normal behavior
    } else if (_batteryLevel >= 25) {
      return 1.5; // Reduce frequency by 50%
    } else if (_batteryLevel >= 15) {
      return 2.0; // Reduce frequency by 100%
    } else {
      return 3.0; // Aggressive power saving
    }
  }

  // ✅ NEW: Dynamic update intervals based on battery and movement for Phase 2
  int _getMinUpdateInterval() {
    int baseInterval = 15; // Base interval in seconds (optimized for 5sec checks)
    
    if (_isDeviceMoving) {
      baseInterval = 10; // More frequent when moving
    } else {
      baseInterval = 30; // Less frequent when stationary
    }
    
    // Apply battery-based multiplier
    final batteryMultiplier = _getBatteryMultiplier();
    return (baseInterval * batteryMultiplier).round();
  }

  // ✅ NEW: Mark position as sent (called after successful API call) for Phase 2
  void markPositionAsSent() {
    if (_currentPosition != null) {
      _lastSentPosition = _currentPosition;
      _lastUpdateTime = DateTime.now();
      print('LocationService: Position marked as sent - '
            'Lat: ${_lastSentPosition!.latitude}, '
            'Lng: ${_lastSentPosition!.longitude}');
    }
  }

  // ✅ NEW: Get filtered position (only returns position if it should be sent) for Phase 2
  Position? getFilteredPosition() {
    if (_shouldSendLocationUpdate()) {
      return _currentPosition;
    }
    return null;
  }

  Future<bool> checkLocationRequirements() async {
    print('LocationService: Checking location requirements...');
    
    final permissionStatus = await permission_handler.Permission.location.status;
    final backgroundPermissionStatus = await permission_handler.Permission.locationAlways.status;
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    
    _hasLocationPermission = permissionStatus.isGranted;
    _hasBackgroundLocationPermission = backgroundPermissionStatus.isGranted;
    _isLocationEnabled = serviceEnabled;
    
    print('LocationService: Permission granted: $_hasLocationPermission');
    print('LocationService: Background permission granted: $_hasBackgroundLocationPermission');
    print('LocationService: Service enabled: $_isLocationEnabled');
    
    return _hasLocationPermission && _hasBackgroundLocationPermission && _isLocationEnabled;
  }

  Future<permission_handler.PermissionStatus> requestLocationPermission() async {
    print('LocationService: Requesting location permission...');
    
    // Request basic location permission first
    final status = await permission_handler.Permission.location.request();
    _hasLocationPermission = status.isGranted;
    
    // Request background location permission
    if (status.isGranted) {
      final backgroundStatus = await permission_handler.Permission.locationAlways.request();
      _hasBackgroundLocationPermission = backgroundStatus.isGranted;
      
      if (!backgroundStatus.isGranted) {
        print('LocationService: Background location permission denied - critical for 24/7 tracking');
      }
    }
    
    // Also request precise location permission on Android
    if (status.isGranted) {
      try {
        final preciseStatus = await permission_handler.Permission.locationWhenInUse.request();
        print('LocationService: Precise location permission: $preciseStatus');
      } catch (e) {
        print('LocationService: Error requesting precise location: $e');
      }
    }
    
    return status;
  }

  Future<Position?> getCurrentPosition({
    LocationAccuracy accuracy = LocationAccuracy.bestForNavigation,
    Duration? timeout,
  }) async {
    if (_isInitializing) {
      print('LocationService: Already initializing, waiting...');
      await Future.delayed(const Duration(seconds: 2));
    }
    
    _isInitializing = true;
    
    try {
      print('LocationService: Getting current position with ${accuracy.toString()} accuracy...');
      
      // First check if we have permission and service is enabled
      final hasRequirements = await checkLocationRequirements();
      if (!hasRequirements) {
        throw 'Location permission or service not available';
      }
      
      // ✅ UPDATED: Initialize battery monitoring on first position request
      if (_batteryCheckTimer == null) {
        await _initializeBatteryMonitoring();
      }
      
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: accuracy,
        timeLimit: timeout ?? const Duration(seconds: 15),
        forceAndroidLocationManager: false, // Use Google Play Services for better accuracy
      );
      
      _currentPosition = position;
      print('LocationService: Position obtained - Lat: ${position.latitude}, Lng: ${position.longitude}, Accuracy: ±${position.accuracy.toStringAsFixed(1)}m');
      
      return position;
    } catch (e) {
      print('LocationService: Error getting current position: $e');
      return null;
    } finally {
      _isInitializing = false;
    }
  }

  // ✅ UPDATED: Enhanced location tracking with smart filtering support
  void startLocationTracking(Function(Position) onLocationUpdate) {
    print('LocationService: Starting location tracking with smart filtering support...');
    
    _onLocationUpdate = onLocationUpdate;
    
    // Stop any existing subscription
    stopLocationTracking();
    
    try {
      // Initialize battery monitoring
      _initializeBatteryMonitoring();
      
      // Get initial position first to provide immediate feedback
      getCurrentPosition().then((initialPosition) {
        if (initialPosition != null) {
          print('LocationService: Initial position obtained, starting stream...');
          _onLocationUpdate?.call(initialPosition);
          // Mark first position as sent
          markPositionAsSent();
        }
      }).catchError((e) {
        print('LocationService: Error getting initial position: $e');
        // Continue with stream anyway
      });
      
      // Start the position stream with optimized settings
      const LocationSettings locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // Get GPS updates every 5 meters (filtering happens in API timer)
        timeLimit: Duration(seconds: 30),
      );
      
      _positionSubscription = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
        (position) {
          _currentPosition = position;
          print('LocationService: GPS Update - Lat: ${position.latitude}, Lng: ${position.longitude}, Speed: ${position.speed.toStringAsFixed(1)}m/s');
          
          // Always call the callback for UI updates
          _onLocationUpdate?.call(position);
          
          // Note: API filtering happens in the main app timer, not here
        },
        onError: (error) {
          print('LocationService: Stream error: $error');
          
          // Try to restart the stream after a delay
          Timer(const Duration(seconds: 5), () {
            print('LocationService: Attempting to restart location stream...');
            if (_onLocationUpdate != null) {
              startLocationTracking(_onLocationUpdate!);
            }
          });
        },
        cancelOnError: false, // Continue tracking even if there are temporary errors
      );
      
      print('LocationService: Location tracking started successfully');
    } catch (e) {
      print('LocationService: Error starting location tracking: $e');
    }
  }

  void stopLocationTracking() {
    print('LocationService: Stopping location tracking...');
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  // ✅ UPDATED: Enhanced dispose with battery timer cleanup
  void dispose() {
    print('LocationService: Disposing...');
    stopLocationTracking();
    _batteryCheckTimer?.cancel();
    _batteryCheckTimer = null;
  }
}