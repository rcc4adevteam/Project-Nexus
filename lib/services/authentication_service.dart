import 'package:project_nexus/services/api_service.dart';
import 'package:project_nexus/services/network_connectivity_service.dart';
import 'package:project_nexus/services/secure_storage_service.dart';

class AuthenticationService {
  static final AuthenticationService _instance = AuthenticationService._internal();
  factory AuthenticationService() => _instance;
  AuthenticationService._internal();

  final NetworkConnectivityService _networkService = NetworkConnectivityService();
  final SecureStorageService _secureStorage = SecureStorageService();
  
  // Session state
  bool _isAuthenticated = false;
  String? _currentToken;
  String? _currentDeploymentCode;
  bool _isOfflineMode = false;
  
  // Getters
  bool get isAuthenticated => _isAuthenticated;
  String? get currentToken => _currentToken;
  String? get currentDeploymentCode => _currentDeploymentCode;
  bool get isOfflineMode => _isOfflineMode;
  
  // Initialize the service
  Future<void> initialize() async {
    try {
      print('AuthenticationService: Initializing...');
      
      // Initialize network service
      await _networkService.initialize();
      
      // Initialize secure storage
      await _secureStorage.initialize();
      
      print('AuthenticationService: Initialized successfully');
    } catch (e) {
      print('AuthenticationService: Error initializing: $e');
      rethrow;
    }
  }
  
  // Check authentication status on app startup
  Future<AuthStatus> checkAuthenticationStatus() async {
    try {
      print('AuthenticationService: Checking authentication status...');
      
      // Check for stored credentials
      final storedToken = await _secureStorage.getToken();
      final storedDeploymentCode = await _secureStorage.getDeploymentCode();
      
      if (storedToken == null || storedDeploymentCode == null) {
        print('AuthenticationService: No stored credentials found');
        return AuthStatus.noCredentials;
      }
      
      // Check network connectivity
      final isOnline = await _networkService.checkConnectivity();
      
      if (isOnline) {
        print('AuthenticationService: Device is online, validating session with server...');
        
        // Try to validate session with server
        try {
          final isValid = await _validateSessionWithServer(storedToken, storedDeploymentCode);
          
          if (isValid) {
            print('AuthenticationService: Session validated successfully with server');
            _setAuthenticatedSession(storedToken, storedDeploymentCode, false);
            return AuthStatus.authenticated;
          } else {
            print('AuthenticationService: Session validation failed with server');
            await _clearInvalidSession();
            return AuthStatus.invalidCredentials;
          }
        } catch (e) {
          print('AuthenticationService: Server validation error: $e');
          // If server validation fails, fall back to offline mode
          print('AuthenticationService: Falling back to offline mode');
          _setAuthenticatedSession(storedToken, storedDeploymentCode, true);
          return AuthStatus.authenticatedOffline;
        }
      } else {
        print('AuthenticationService: Device is offline, using stored credentials');
        
        // Device is offline, use stored credentials
        _setAuthenticatedSession(storedToken, storedDeploymentCode, true);
        return AuthStatus.authenticatedOffline;
      }
    } catch (e) {
      print('AuthenticationService: Error checking authentication status: $e');
      return AuthStatus.error;
    }
  }
  
  // Validate session with server
  Future<bool> _validateSessionWithServer(String token, String deploymentCode) async {
    try {
      final response = await ApiService.checkStatus(token, deploymentCode);
      
      if (response.success && response.data != null) {
        final isLoggedIn = response.data!['isLoggedIn'] ?? false;
        return isLoggedIn;
      }
      
      return false;
    } catch (e) {
      print('AuthenticationService: Server validation error: $e');
      rethrow;
    }
  }
  
  // Set authenticated session
  void _setAuthenticatedSession(String token, String deploymentCode, bool offlineMode) {
    _currentToken = token;
    _currentDeploymentCode = deploymentCode;
    _isAuthenticated = true;
    _isOfflineMode = offlineMode;
    
    print('AuthenticationService: Session set - Token: ${token.substring(0, 8)}..., Offline: $offlineMode');
  }
  
  // Clear invalid session (keep token persistent as requested)
  Future<void> _clearInvalidSession() async {
    try {
      // Do NOT clear token; only clear deployment code to require relogin with code
      await _secureStorage.clearDeploymentCode();
      
      // Keep token cached
      // _currentToken persists; clear only in-memory deployment code and flags
      _currentDeploymentCode = null;
      _isAuthenticated = false;
      _isOfflineMode = false;
      
      print('AuthenticationService: Invalid session cleared (token preserved)');
    } catch (e) {
      print('AuthenticationService: Error clearing invalid session: $e');
    }
  }
  
  // Login user
  Future<AuthResult> login(String token, String deploymentCode) async {
    try {
      print('AuthenticationService: Attempting login...');
      
      // Check network connectivity
      final isOnline = await _networkService.checkConnectivity();
      
      if (isOnline) {
        // Try to validate with server
        try {
          final response = await ApiService.login(token, deploymentCode);
          
          if (response.success) {
            // Store credentials securely
            await _secureStorage.storeToken(token);
            await _secureStorage.storeDeploymentCode(deploymentCode);
            
            // Set authenticated session
            _setAuthenticatedSession(token, deploymentCode, false);
            
            print('AuthenticationService: Login successful with server validation');
            return AuthResult.success;
          } else {
            print('AuthenticationService: Login failed: ${response.message}');
            return AuthResult.failure(response.message);
          }
        } catch (e) {
          print('AuthenticationService: Server login error: $e');
          return AuthResult.failure('Network error during login');
        }
      } else {
        // Offline mode - store credentials without server validation
        await _secureStorage.storeToken(token);
        await _secureStorage.storeDeploymentCode(deploymentCode);
        
        // Set authenticated session in offline mode
        _setAuthenticatedSession(token, deploymentCode, true);
        
        print('AuthenticationService: Login successful in offline mode');
        return AuthResult.successOffline;
      }
    } catch (e) {
      print('AuthenticationService: Login error: $e');
      return AuthResult.failure('Unexpected error during login');
    }
  }
  
  // Logout user
  Future<void> logout() async {
    try {
      print('AuthenticationService: Logging out...');
      
      // Try to notify server if online
      if (_isAuthenticated && !_isOfflineMode && _currentToken != null && _currentDeploymentCode != null) {
        try {
          final isOnline = await _networkService.checkConnectivity();
          if (isOnline) {
            await ApiService.logout(_currentToken!, _currentDeploymentCode!);
          }
        } catch (e) {
          print('AuthenticationService: Server logout error (non-critical): $e');
        }
      }
      
      // Clear local session
      await _clearInvalidSession();
      
      print('AuthenticationService: Logout completed');
    } catch (e) {
      print('AuthenticationService: Error during logout: $e');
    }
  }
  
  // Check if we can transition from offline to online mode
  Future<bool> tryOnlineValidation() async {
    if (!_isOfflineMode || !_isAuthenticated) return false;
    
    try {
      final isOnline = await _networkService.checkConnectivity();
      if (!isOnline) return false;
      
      // Try to validate with server
      if (_currentToken != null && _currentDeploymentCode != null) {
        final isValid = await _validateSessionWithServer(_currentToken!, _currentDeploymentCode!);
        
        if (isValid) {
          // Transition to online mode
          _isOfflineMode = false;
          print('AuthenticationService: Successfully transitioned from offline to online mode');
          return true;
        } else {
          // Session is invalid, clear it
          await _clearInvalidSession();
          print('AuthenticationService: Session invalid during online validation, cleared');
          return false;
        }
      }
      
      return false;
    } catch (e) {
      print('AuthenticationService: Error during online validation: $e');
      return false;
    }
  }
  
  // Dispose resources
  void dispose() {
    _networkService.dispose();
  }
}

// Authentication status enum
enum AuthStatus {
  noCredentials,        // No stored credentials
  authenticated,        // Valid online session
  authenticatedOffline, // Valid offline session
  invalidCredentials,   // Stored credentials are invalid
  error,               // Error occurred
}

// Authentication result class to handle success/failure with messages
class AuthResult {
  final bool isSuccess;
  final bool isOffline;
  final String? errorMessage;
  
  const AuthResult._({
    required this.isSuccess,
    required this.isOffline,
    this.errorMessage,
  });
  
  // Factory constructors
  static const AuthResult success = AuthResult._(isSuccess: true, isOffline: false);
  static const AuthResult successOffline = AuthResult._(isSuccess: true, isOffline: true);
  
  static AuthResult failure(String message) => AuthResult._(
    isSuccess: false, 
    isOffline: false, 
    errorMessage: message
  );
  
  // Getters for backward compatibility
  bool get isFailure => !isSuccess;
}
