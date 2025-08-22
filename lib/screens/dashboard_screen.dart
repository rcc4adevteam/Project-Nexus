import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/location_service.dart';
import '../services/device_service.dart';
import '../services/api_service.dart';
import '../services/background_service.dart';
import '../services/watchdog_service.dart';
import '../services/wake_lock_service.dart';
import '../widgets/metric_card.dart';
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

class _DashboardScreenState extends State<DashboardScreen> {
  final _locationService = LocationService();
  final _deviceService = DeviceService();
  final _watchdogService = WatchdogService();
  final _wakeLockService = WakeLockService();

  Timer? _apiUpdateTimer;
  Timer? _heartbeatTimer;
  bool _isLoading = true;
  bool _isLocationLoading = true;
  double _internetSpeed = 0.0;
  bool _hasInitialized = false;
  bool hasInternet = false;
  Map<String, dynamic> _watchdogStatus = {};
  Map<String, dynamic> _wakeLockStatus = {};

  @override
  void initState() {
    super.initState();
    print(
        'Dashboard: initState called with token: ${widget.token.substring(0, 10)}...');
    _initializeServices();
  }

  @override
  void dispose() {
    _apiUpdateTimer?.cancel();
    _heartbeatTimer?.cancel();
    _locationService.dispose();
    _deviceService.dispose();
    _watchdogService.stopWatchdog();
    // Don't dispose wake lock here - keep it running for continuous monitoring
    super.dispose();
  }

  Future<void> _initializeServices() async {
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      print('Dashboard: Starting service initialization...');

      // Initialize core services including permanent wake lock
      await Future.wait([
        _initializeDeviceService(),
        _initializeLocationTracking(),
        _initializeWatchdog(),
        _initializePermanentWakeLock(), // Built-in wake lock
      ], eagerError: false);

      // Start periodic updates
      _startPeriodicUpdates();

      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasInitialized = true;
        });
        print('Dashboard: Initialization completed successfully');
      }
    } catch (e) {
      print('Dashboard: Error during initialization: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Initialization error: ${e.toString()}'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _initializeDeviceService() async {
    try {
      await _deviceService.initialize();
      print('Dashboard: Device service initialized successfully');
    } catch (e) {
      print('Dashboard: Error initializing device service: $e');
    }
  }

  Future<void> _initializeWatchdog() async {
    try {
      await _watchdogService.initialize(
        onAppDead: () {
          print('Dashboard: App death detected by watchdog');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'App monitoring was interrupted. Restarting services...'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 5),
              ),
            );
            // Try to restart services
            _initializeServices();
          }
        },
      );
      _watchdogService.startWatchdog();
      print('Dashboard: Watchdog initialized and started');
    } catch (e) {
      print('Dashboard: Error initializing watchdog: $e');
    }
  }

  // Built-in wake lock - no user control, always enabled
  Future<void> _initializePermanentWakeLock() async {
    try {
      await _wakeLockService.initialize();

      // Force enable wake lock permanently for 24/7 monitoring
      await _wakeLockService.forceEnableForCriticalOperation();

      if (mounted) {
        setState(() {
          _wakeLockStatus = _wakeLockService.getDetailedStatus();
        });
      }

      print('Dashboard: Permanent wake lock enabled for 24/7 monitoring');
    } catch (e) {
      print('Dashboard: Error initializing permanent wake lock: $e');
      // Try again after delay
      Timer(const Duration(seconds: 5), () {
        _initializePermanentWakeLock();
      });
    }
  }

  Future<void> _initializeLocationTracking() async {
    if (!mounted) return;

    setState(() => _isLocationLoading = true);

    try {
      print('Dashboard: Initializing high-precision location tracking...');

      final hasAccess = await _locationService.checkLocationRequirements();
      if (hasAccess) {
        // Ensure wake lock is active for location tracking
        await _wakeLockService.forceEnableForCriticalOperation();

        // Get initial high-precision location
        final position = await _locationService.getCurrentPosition(
          accuracy: LocationAccuracy.bestForNavigation,
          timeout: const Duration(seconds: 15),
        );

        if (position != null) {
          print(
              'Dashboard: Initial high-precision location obtained: ${position.latitude}, ${position.longitude}, accuracy: ±${position.accuracy.toStringAsFixed(1)}m');
          if (mounted) {
            setState(() => _isLocationLoading = false);
          }
        }

        // Start high-precision continuous tracking
        _locationService.startHighPrecisionTracking(
          onLocationUpdate: (position) {
            if (mounted) {
              setState(() => _isLocationLoading = false);
              print(
                  'Dashboard: High-precision location updated: ${position.latitude}, ${position.longitude}, accuracy: ±${position.accuracy.toStringAsFixed(1)}m, speed: ${position.speed.toStringAsFixed(1)}m/s');
            }
          },
          onError: (error) {
            print('Dashboard: Location tracking error: $error');
            if (mounted) {
              setState(() => _isLocationLoading = false);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Location tracking error: $error'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
          },
        );

        // Add a timeout to stop loading state even if no location updates come
        Timer(const Duration(seconds: 20), () {
          if (mounted && _isLocationLoading) {
            setState(() => _isLocationLoading = false);
            print(
                'Dashboard: Location loading timeout - stopping loading indicator');
          }
        });
      } else {
        print('Dashboard: High-precision location access not available');
        if (mounted) {
          setState(() => _isLocationLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'High-precision location requires GPS and location permissions'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print(
          'Dashboard: Error initializing high-precision location tracking: $e');
      if (mounted) {
        setState(() => _isLocationLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to initialize high-precision location: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _startPeriodicUpdates() {
    // API updates
    _apiUpdateTimer = Timer.periodic(
      AppSettings.apiUpdateInterval,
      (timer) => _sendLocationUpdateSafely(),
    );

    // Watchdog heartbeat and wake lock maintenance
    _heartbeatTimer = Timer.periodic(
      const Duration(minutes: 5),
      (timer) {
        _watchdogService.ping();

        // Ensure wake lock stays enabled (built-in maintenance)
        _maintainWakeLock();

        if (mounted) {
          setState(() {
            _watchdogStatus = _watchdogService.getStatus();
            _wakeLockStatus = _wakeLockService.getDetailedStatus();
          });
        }
      },
    );

    // Internet speed simulation
    Timer.periodic(const Duration(seconds: 15), (timer) {
      if (mounted) {
        setState(() {
          _internetSpeed =
              100 + (DateTime.now().millisecondsSinceEpoch % 1000) / 10;
        });
      }
    });
  }

  // Maintain wake lock automatically
  Future<void> _maintainWakeLock() async {
    try {
      final isEnabled = await _wakeLockService.checkWakeLockStatus();
      if (!isEnabled) {
        print(
            'Dashboard: Wake lock disabled, re-enabling for continuous monitoring...');
        await _wakeLockService.forceEnableForCriticalOperation();
      }
    } catch (e) {
      print('Dashboard: Error maintaining wake lock: $e');
    }
  }

  Future<void> _sendLocationUpdateSafely() async {
    try {
      await _sendLocationUpdate();
    } catch (e) {
      print('Dashboard: Error sending location update: $e');
    }
  }

  Future<void> _sendLocationUpdate() async {
    final position = _locationService.currentPosition;
    if (position == null) return;

    await ApiService.updateLocation(
      token: widget.token,
      deploymentCode: widget.deploymentCode,
      position: position,
      batteryLevel: _deviceService.batteryLevel,
      signalStrength: _deviceService.signalStrength,
    );
  }

  Color _getBatteryColor() {
    final level = _deviceService.batteryLevel;
    if (level > 50) return Colors.green;
    if (level > 20) return Colors.orange;
    return Colors.red;
  }

  IconData _getBatteryIcon() {
    final level = _deviceService.batteryLevel;
    final state = _deviceService.batteryState;

    if (state.toString().contains('charging'))
      return Icons.battery_charging_full;
    if (level > 80) return Icons.battery_full;
    if (level > 60) return Icons.battery_6_bar;
    if (level > 40) return Icons.battery_4_bar;
    if (level > 20) return Icons.battery_2_bar;
    return Icons.battery_1_bar;
  }

  Color _getSignalColor() {
    switch (_deviceService.signalStrength) {
      case 'strong':
        return Colors.green;
      case 'weak':
        return Colors.orange;
      default:
        return Colors.red;
    }
  }

  Future<void> _refreshLocation() async {
    setState(() => _isLocationLoading = true);

    try {
      print('Dashboard: Force refreshing high-precision location...');

      final position = await _locationService.forceLocationRefresh();
      if (position != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'High-precision location refreshed (±${position.accuracy.toStringAsFixed(1)}m)'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Failed to get high-precision location. Try moving outdoors.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      print('Dashboard: Error refreshing high-precision location: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to refresh location: $e'),
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

  Future<void> _showLogoutConfirmation() async {
    bool hasInternet = false;

    // Check internet when dialog opens
    var connectivityResult = await Connectivity().checkConnectivity();
    hasInternet = connectivityResult != ConnectivityResult.none;

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            // Listen for connectivity changes while dialog is open
            Connectivity().onConnectivityChanged.listen((result) {
              bool newHasInternet = result != ConnectivityResult.none;
              if (newHasInternet != hasInternet) {
                setState(() {
                  hasInternet = newHasInternet;
                });
              }
            });

            return AlertDialog(
              title: Row(
                children: const [
                  Icon(Icons.logout, color: Colors.orange, size: 24),
                  SizedBox(width: 8),
                  Text('Confirm Logout'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Are you sure you want to logout?',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  const Text('This will:'),
                  const SizedBox(height: 8),
                  const Text('• Stop location tracking'),
                  const Text('• Stop background monitoring'),
                  const Text('• Clear saved credentials'),
                  const Text('• Return you to login screen'),
                  const SizedBox(height: 16),

                  // ⚠️ Warning message when no internet
                  if (!hasInternet) ...[
                    const Divider(),
                    Row(
                      children: const [
                        Icon(Icons.warning, color: Colors.red, size: 20),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'No internet connection detected.\nLogout is disabled until connection is restored.',
                            style: TextStyle(color: Colors.red, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  child: const Text('Cancel'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        hasInternet ? Colors.red : Colors.grey, // 🔴 or 🔒
                    foregroundColor: Colors.white,
                  ),
                  onPressed: hasInternet
                      ? () {
                          Navigator.of(context).pop();
                          _performLogout();
                        }
                      : null, // 🚫 Disabled when offline
                  child: const Text('Logout'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _executeCancellableAction(
      String title, Future<void> Function() action) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(title),
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

  Future<void> _performLogout() async {
    await _executeCancellableAction('Logging out...', () async {
      await ApiService.logout(widget.token, widget.deploymentCode);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('token');
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Device Monitor Dashboard'),
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: _showLogoutConfirmation,
              tooltip: 'Logout',
            ),
          ],
        ),
        body: _isLoading
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Initializing Dashboard...'),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: _initializeServices,
                child: ListView(
                  padding: const EdgeInsets.all(16.0),
                  children: [
                    // Status Card with built-in wake lock
                    Card(
                      color: Colors.green[900],
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle, color: Colors.green),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'High-Precision Monitoring Active',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                                  ),
                                  Text(
                                    '24/7 GPS tracking • Wake lock enabled • Continuous monitoring',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.screen_lock_rotation,
                                color: Colors.green),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Watchdog Status Card
                    if (_watchdogStatus.isNotEmpty) ...[
                      Card(
                        color: (_watchdogStatus['isRunning'] ?? false)
                            ? Colors.blue[900]
                            : Colors.orange[900],
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            children: [
                              Icon(
                                (_watchdogStatus['isRunning'] ?? false)
                                    ? Icons.security
                                    : Icons.warning,
                                color: (_watchdogStatus['isRunning'] ?? false)
                                    ? Colors.blue
                                    : Colors.orange,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (_watchdogStatus['isRunning'] ?? false)
                                          ? 'Watchdog Active'
                                          : 'Watchdog Stopped',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: (_watchdogStatus['isRunning'] ??
                                                false)
                                            ? Colors.blue
                                            : Colors.orange,
                                      ),
                                    ),
                                    Text(
                                      (_watchdogStatus['isRunning'] ?? false)
                                          ? 'Monitoring app health every 15 minutes'
                                          : 'App monitoring disabled',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    MetricCard(
                      title: 'Battery',
                      icon: _getBatteryIcon(),
                      iconColor: _getBatteryColor(),
                      value: '${_deviceService.batteryLevel}%',
                      subtitle: _deviceService.batteryState
                          .toString()
                          .split('.')
                          .last
                          .toUpperCase(),
                      isRealTime: true,
                    ),
                    MetricCard(
                      title: 'Signal Strength',
                      icon: Icons.signal_cellular_alt,
                      iconColor: _getSignalColor(),
                      value: _deviceService.signalStrength.toUpperCase(),
                      subtitle: _deviceService.connectivityResult
                          .toString()
                          .split('.')
                          .last
                          .toUpperCase(),
                      isRealTime: true,
                    ),
                    MetricCard(
                      title: 'Internet Speed',
                      icon: Icons.speed,
                      iconColor: Colors.blue,
                      value: '${_internetSpeed.toStringAsFixed(1)} KB/s',
                      subtitle: 'SIMULATED DATA',
                      isRealTime: true,
                    ),

                    _buildLocationCard(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildLocationCard() {
    if (!_locationService.hasLocationPermission) {
      return Card(
        color: Colors.orange[900],
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              const Icon(Icons.location_off, size: 48, color: Colors.orange),
              const SizedBox(height: 12),
              const Text(
                'Location Permission Required',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Grant location permission to enable high-precision tracking',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () async {
                  try {
                    await _locationService.requestLocationPermission();
                    await _initializeLocationTracking();
                  } catch (e) {
                    print(
                        'Dashboard: Error requesting location permission: $e');
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.black,
                ),
                child: const Text('Enable High-Precision Location'),
              ),
            ],
          ),
        ),
      );
    }

    if (_isLocationLoading) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              const Text('Acquiring high-precision location...'),
              const SizedBox(height: 8),
              Text(
                'Using GPS + Network for best accuracy',
                style: TextStyle(color: Colors.grey[400], fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    final position = _locationService.currentPosition;
    if (position == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Icon(Icons.location_searching, size: 48, color: Colors.grey[600]),
              const SizedBox(height: 12),
              const Text('High-Precision Location Unavailable'),
              const SizedBox(height: 8),
              Text(
                'Unable to get precise location. Please ensure GPS is enabled.',
                style: TextStyle(color: Colors.grey[400], fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _refreshLocation,
                icon: const Icon(Icons.my_location),
                label: const Text('Force GPS Refresh'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.tealAccent,
                  foregroundColor: Colors.black,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final accuracy = position.accuracy;
    final isHighAccuracy = accuracy <= 10;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: (isHighAccuracy ? Colors.green : Colors.orange)
                            .withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                          isHighAccuracy ? Icons.gps_fixed : Icons.location_on,
                          color: isHighAccuracy ? Colors.green : Colors.orange,
                          size: 32),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Flexible(
                                child: Text(
                                  'High-Precision Location',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: (isHighAccuracy
                                          ? Colors.green
                                          : Colors.orange)
                                      .withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  isHighAccuracy ? 'PRECISE' : 'SEARCHING',
                                  style: TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                      color: isHighAccuracy
                                          ? Colors.green
                                          : Colors.orange),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Lat: ${position.latitude.toStringAsFixed(6)}°',
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Lng: ${position.longitude.toStringAsFixed(6)}°',
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _refreshLocation,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Refresh',
                            style: TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.tealAccent,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          final coordinates =
                              '${position.latitude}, ${position.longitude}';
                          Clipboard.setData(ClipboardData(text: coordinates));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Coordinates copied!')),
                          );
                        },
                        icon: const Icon(Icons.copy, size: 16),
                        label:
                            const Text('Copy', style: TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.center_focus_strong,
                          color: Colors.grey[400], size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Accuracy: ${_locationService.getAccuracyStatus()}',
                          style:
                              TextStyle(color: Colors.grey[400], fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.satellite, color: Colors.grey[400], size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Source: ${_locationService.getLocationSource()}',
                          style:
                              TextStyle(color: Colors.grey[400], fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.speed, color: Colors.grey[400], size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Speed: ${position.speed.toStringAsFixed(1)} m/s • ${_locationService.getMovementStatus()}',
                          style:
                              TextStyle(color: Colors.grey[400], fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (position.speed > 0.1) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[900]?.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.navigation,
                            color: Colors.blue, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Heading: ${position.heading.toStringAsFixed(0)}°',
                            style: const TextStyle(
                                color: Colors.lightBlue, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.directions_car,
                            color: Colors.blue, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Speed: ${(position.speed * 3.6).toStringAsFixed(1)} km/h',
                            style: const TextStyle(
                                color: Colors.lightBlue, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (position.altitude.abs() > 1) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green[900]?.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.terrain, color: Colors.green, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Altitude: ${position.altitude.toStringAsFixed(0)}m • Updated: ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                            color: Colors.lightGreen, fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
