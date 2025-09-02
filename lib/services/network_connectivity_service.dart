import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

class NetworkConnectivityService {
  static final NetworkConnectivityService _instance = NetworkConnectivityService._internal();
  factory NetworkConnectivityService() => _instance;
  NetworkConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  
  bool _isOnline = false;
  ConnectivityResult _connectivityResult = ConnectivityResult.none;
  
  // Stream controller for connectivity changes
  final StreamController<bool> _connectivityController = StreamController<bool>.broadcast();
  
  // Getter for current online status
  bool get isOnline => _isOnline;
  
  // Getter for current connectivity result
  ConnectivityResult get connectivityResult => _connectivityResult;
  
  // Stream for listening to connectivity changes
  Stream<bool> get onConnectivityChanged => _connectivityController.stream;
  
  // Initialize the service
  Future<void> initialize() async {
    try {
      print('NetworkConnectivityService: Initializing...');
      
      // Get initial connectivity status
      await _updateConnectivityInfo();
      
      // Listen for connectivity changes
      _connectivitySubscription = _connectivity.onConnectivityChanged.listen((result) {
        _connectivityResult = result;
        final wasOnline = _isOnline;
        _isOnline = result != ConnectivityResult.none;
        
        print('NetworkConnectivityService: Connectivity changed to $result (${_isOnline ? "online" : "offline"})');
        
        // Only notify if the online status actually changed
        if (wasOnline != _isOnline) {
          _connectivityController.add(_isOnline);
        }
      });
      
      print('NetworkConnectivityService: Initialized successfully');
    } catch (e) {
      print('NetworkConnectivityService: Error initializing: $e');
      rethrow;
    }
  }
  
  // Check current connectivity status
  Future<bool> checkConnectivity() async {
    try {
      await _updateConnectivityInfo();
      return _isOnline;
    } catch (e) {
      print('NetworkConnectivityService: Error checking connectivity: $e');
      return false;
    }
  }
  
  // Update connectivity information
  Future<void> _updateConnectivityInfo() async {
    try {
      _connectivityResult = await _connectivity.checkConnectivity();
      _isOnline = _connectivityResult != ConnectivityResult.none;
      print('NetworkConnectivityService: Connectivity updated - Result: $_connectivityResult, Online: $_isOnline');
    } catch (e) {
      print('NetworkConnectivityService: Error updating connectivity info: $e');
      _isOnline = false;
    }
  }
  
  // Get connectivity description
  String getConnectivityDescription() {
    if (!_isOnline) return 'Offline - No internet connection';
    
    switch (_connectivityResult) {
      case ConnectivityResult.wifi:
        return 'WiFi - Online';
      case ConnectivityResult.mobile:
        return 'Mobile Data - Online';
      case ConnectivityResult.ethernet:
        return 'Ethernet - Online';
      case ConnectivityResult.bluetooth:
        return 'Bluetooth - Online';
      default:
        return 'Unknown - Online';
    }
  }
  
  // Check if we can reach the internet (ping test)
  Future<bool> canReachInternet() async {
    if (!_isOnline) return false;
    
    try {
      // Try to reach a reliable host (Google's DNS)
      final result = await Connectivity().checkConnectivity();
      return result != ConnectivityResult.none;
    } catch (e) {
      print('NetworkConnectivityService: Error checking internet reachability: $e');
      return false;
    }
  }
  
  // Dispose resources
  void dispose() {
    print('NetworkConnectivityService: Disposing...');
    _connectivitySubscription?.cancel();
    _connectivityController.close();
  }
}
