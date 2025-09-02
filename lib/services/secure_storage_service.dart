import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';

class SecureStorageService {
  static final SecureStorageService _instance = SecureStorageService._internal();
  factory SecureStorageService() => _instance;
  SecureStorageService._internal();

  static SharedPreferences? _prefs;

  // Generate a unique device identifier for additional security
  static const String _deviceIdKey = 'device_unique_id';
  static const String _saltKey = 'security_salt';
  static const String _tokenKey = 'encrypted_token';
  static const String _deploymentCodeKey = 'encrypted_deployment_code';
  static const String _sessionDataKey = 'encrypted_session_data';

  // Initialize secure storage with device-specific encryption
  Future<void> initialize() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      
      // Generate or retrieve device ID
      String? deviceId = _prefs?.getString(_deviceIdKey);
      if (deviceId == null) {
        deviceId = _generateDeviceId();
        await _prefs?.setString(_deviceIdKey, deviceId);
      }

      // Generate or retrieve security salt
      String? salt = _prefs?.getString(_saltKey);
      if (salt == null) {
        salt = _generateSalt();
        await _prefs?.setString(_saltKey, salt);
      }

      print('SecureStorage: Initialized with device ID: ${deviceId.substring(0, 8)}...');
    } catch (e) {
      print('SecureStorage: Error initializing: $e');
      rethrow;
    }
  }

  // Store encrypted token
  Future<void> storeToken(String token) async {
    try {
      final encryptedToken = await _encryptData(token, _tokenKey);
      await _prefs?.setString(_tokenKey, encryptedToken);
      print('SecureStorage: Token encrypted and stored successfully');
    } catch (e) {
      print('SecureStorage: Error storing token: $e');
      rethrow;
    }
  }

  // Retrieve and decrypt token
  Future<String?> getToken() async {
    try {
      final encryptedToken = _prefs?.getString(_tokenKey);
      if (encryptedToken == null) return null;
      
      final decryptedToken = await _decryptData(encryptedToken, _tokenKey);
      return decryptedToken;
    } catch (e) {
      print('SecureStorage: Error retrieving token: $e');
      return null;
    }
  }

  // Store encrypted deployment code
  Future<void> storeDeploymentCode(String deploymentCode) async {
    try {
      final encryptedCode = await _encryptData(deploymentCode, _deploymentCodeKey);
      await _prefs?.setString(_deploymentCodeKey, encryptedCode);
      print('SecureStorage: Deployment code encrypted and stored successfully');
    } catch (e) {
      print('SecureStorage: Error storing deployment code: $e');
      rethrow;
    }
  }

  // Retrieve and decrypt deployment code
  Future<String?> getDeploymentCode() async {
    try {
      final encryptedCode = _prefs?.getString(_deploymentCodeKey);
      if (encryptedCode == null) return null;
      
      final decryptedCode = await _decryptData(encryptedCode, _deploymentCodeKey);
      return decryptedCode;
    } catch (e) {
      print('SecureStorage: Error retrieving deployment code: $e');
      return null;
    }
  }

  // Store encrypted session data
  Future<void> storeSessionData(Map<String, dynamic> sessionData) async {
    try {
      final jsonData = json.encode(sessionData);
      final encryptedData = await _encryptData(jsonData, _sessionDataKey);
      await _prefs?.setString(_sessionDataKey, encryptedData);
      print('SecureStorage: Session data encrypted and stored successfully');
    } catch (e) {
      print('SecureStorage: Error storing session data: $e');
      rethrow;
    }
  }

  // Retrieve and decrypt session data
  Future<Map<String, dynamic>?> getSessionData() async {
    try {
      final encryptedData = _prefs?.getString(_sessionDataKey);
      if (encryptedData == null) return null;
      
      final decryptedData = await _decryptData(encryptedData, _sessionDataKey);
      final sessionData = json.decode(decryptedData) as Map<String, dynamic>;
      return sessionData;
    } catch (e) {
      print('SecureStorage: Error retrieving session data: $e');
      return null;
    }
  }

  // Clear all stored data
  Future<void> clearAllData() async {
    try {
      await _prefs?.clear();
      print('SecureStorage: All data cleared successfully');
    } catch (e) {
      print('SecureStorage: Error clearing data: $e');
      rethrow;
    }
  }

  // Clear stored token
  Future<void> clearToken() async {
    try {
      await _prefs?.remove(_tokenKey);
      print('SecureStorage: Token cleared successfully');
    } catch (e) {
      print('SecureStorage: Error clearing token: $e');
      rethrow;
    }
  }

  // Clear stored deployment code
  Future<void> clearDeploymentCode() async {
    try {
      await _prefs?.remove(_deploymentCodeKey);
      print('SecureStorage: Deployment code cleared successfully');
    } catch (e) {
      print('SecureStorage: Error clearing deployment code: $e');
      rethrow;
    }
  }

  // Check if user is authenticated
  Future<bool> isAuthenticated() async {
    try {
      final token = await getToken();
      final deploymentCode = await getDeploymentCode();
      return token != null && deploymentCode != null;
    } catch (e) {
      print('SecureStorage: Error checking authentication: $e');
      return false;
    }
  }

  // Encrypt data with device-specific key
  Future<String> _encryptData(String data, String keyType) async {
    try {
      final deviceId = _prefs?.getString(_deviceIdKey) ?? '';
      final salt = _prefs?.getString(_saltKey) ?? '';
      
      // Create a unique encryption key for this data type
      final encryptionKey = _generateEncryptionKey(deviceId, salt, keyType);
      
      // Simple XOR encryption (in production, use proper encryption libraries)
      final encryptedBytes = <int>[];
      for (int i = 0; i < data.codeUnits.length; i++) {
        encryptedBytes.add(data.codeUnits[i] ^ encryptionKey[i % encryptionKey.length]);
      }
      
      return base64.encode(encryptedBytes);
    } catch (e) {
      print('SecureStorage: Error encrypting data: $e');
      rethrow;
    }
  }

  // Decrypt data with device-specific key
  Future<String> _decryptData(String encryptedData, String keyType) async {
    try {
      final deviceId = _prefs?.getString(_deviceIdKey) ?? '';
      final salt = _prefs?.getString(_saltKey) ?? '';
      
      // Create the same encryption key
      final encryptionKey = _generateEncryptionKey(deviceId, salt, keyType);
      
      // Decrypt using XOR
      final encryptedBytes = base64.decode(encryptedData);
      final decryptedBytes = <int>[];
      for (int i = 0; i < encryptedBytes.length; i++) {
        decryptedBytes.add(encryptedBytes[i] ^ encryptionKey[i % encryptionKey.length]);
      }
      
      return String.fromCharCodes(decryptedBytes);
    } catch (e) {
      print('SecureStorage: Error decrypting data: $e');
      rethrow;
    }
  }

  // Generate encryption key from device ID, salt, and key type
  List<int> _generateEncryptionKey(String deviceId, String salt, String keyType) {
    final combined = '$deviceId$salt$keyType';
    final hash = sha256.convert(combined.codeUnits);
    return hash.bytes;
  }

  // Generate unique device identifier
  String _generateDeviceId() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (i) => random.nextInt(256));
    return base64.encode(bytes);
  }

  // Generate security salt
  String _generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (i) => random.nextInt(256));
    return base64.encode(bytes);
  }
}
