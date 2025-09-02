import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import '../services/location_service.dart';
import '../services/api_service.dart';
import '../services/background_service.dart';
import '../services/watchdog_service.dart';
import '../services/authentication_service.dart';
import '../services/update_service.dart';
import '../utils/constants.dart';
import '../widgets/update_dialog.dart';
import 'dashboard_screen.dart';
import 'location_screen.dart';

// QR Scanner Screen
class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  bool _isPopped = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan QR Code')),
      body: MobileScanner(
        onDetect: (capture) {
          if (_isPopped) return;

          final List<Barcode> barcodes = capture.barcodes;
          if (barcodes.isNotEmpty) {
            final String? code = barcodes.first.rawValue;
            if (code != null) {
              _isPopped = true;
              Navigator.pop(context, code);
            }
          }
        },
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _tokenController = TextEditingController();
  final _deploymentCodeController = TextEditingController();
  final _locationService = LocationService();
  final _watchdogService = WatchdogService();
  final _authService = AuthenticationService();
  
  bool _isDeploymentCodeVisible = false;
  bool _isLoading = false;
  bool _isLocationChecking = false;
  String _appVersion = '';
  bool _hasStoredCredentials = false;
  bool _isTokenLocked = false;
  Timer? _deploymentCodeTimer;
  
  // ENHANCED: Track deployment code validation status
  bool _isDeploymentCodeInUse = false;
  bool _isCheckingDeploymentCode = false;
  bool _isDeploymentCodeValid = false;
  String _lastCheckedDeploymentCode = '';
  String _deploymentCodeStatus = '';

  @override
  void initState() {
    super.initState();
    _initializeScreen();
  }

  @override
  void dispose() {
    _deploymentCodeTimer?.cancel();
    _authService.dispose();
    super.dispose();
  }

  Future<void> _initializeScreen() async {
    await _getAppVersion();
    await _loadStoredCredentials();
    await _initializeWatchdog();
  }

  Future<void> _getAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _appVersion = packageInfo.version);
  }

  Future<void> _loadStoredCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final storedToken = prefs.getString('token');
    final isTokenLocked = prefs.getBool('isTokenLocked') ?? false;

    if (storedToken != null && isTokenLocked) {
      if (mounted) {
        setState(() {
          _tokenController.text = storedToken;
          _hasStoredCredentials = true;
          _isTokenLocked = true;
        });
      }
    }
  }
  
  Future<void> _initializeWatchdog() async {
    await _watchdogService.initialize();
    await _watchdogService.markAppAsAlive();
    final wasAppDead = await _watchdogService.wasAppDead();
    if (wasAppDead && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('App monitoring was interrupted. Please login again.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _uploadTokenFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt'],
        withData: true,
      );

      if (result != null && result.files.single.bytes != null) {
        final token = utf8.decode(result.files.single.bytes!);
        setState(() {
          _tokenController.text = token.trim();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Token loaded successfully from file.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to read file: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  Future<void> _scanQRCodeForToken() async {
    final scannedCode = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const QRScannerScreen()),
    );

    if (scannedCode != null && mounted) {
      // Clean and extract plain text value
      final cleanedCode = _extractPlainTextFromQR(scannedCode);
      
      // Check if the QR contains both token and deployment code (separated by |)
      final parts = cleanedCode.split('|');
      if (parts.length == 2) {
        setState(() {
          _tokenController.text = parts[0].trim();
          _deploymentCodeController.text = parts[1].trim();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Token and Deployment Code loaded from QR.'),
            backgroundColor: Colors.green,
          ),
        );
        // Trigger validation for the scanned deployment code
        _onDeploymentCodeChanged(parts[1].trim());
      } else {
        setState(() {
          _tokenController.text = cleanedCode.trim();
          _deploymentCodeController.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Token loaded from QR. Please enter Deployment Code.'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    }
  }
  
  Future<void> _scanQRCodeForDeployment() async {
    final scannedCode = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const QRScannerScreen()),
    );

    if (scannedCode != null && mounted) {
      // Clean and extract plain text value
      final cleanedCode = _extractPlainTextFromQR(scannedCode);
      
      setState(() {
        _deploymentCodeController.text = cleanedCode.trim();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Deployment Code loaded from QR.'),
          backgroundColor: Colors.blue,
        ),
      );
      // Trigger validation for the scanned deployment code
      _onDeploymentCodeChanged(cleanedCode.trim());
    }
  }

  // Helper function to extract plain text from QR code
  String _extractPlainTextFromQR(String qrData) {
    // Remove any potential formatting, encoding artifacts, or extra characters
    String cleanedData = qrData;
    
    // Remove common QR code prefixes if they exist
    if (cleanedData.startsWith('TEXT:')) {
      cleanedData = cleanedData.substring(5);
    }
    
    // Remove any leading/trailing whitespace, newlines, or special characters
    cleanedData = cleanedData.trim();
    cleanedData = cleanedData.replaceAll(RegExp(r'[\r\n\t]'), '');
    
    // Remove any null characters or non-printable characters
    cleanedData = cleanedData.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');
    
    print('QR Scanner: Original data: "$qrData"');
    print('QR Scanner: Cleaned data: "$cleanedData"');
    
    return cleanedData;
  }

  // ENHANCED: Check deployment code with comprehensive validation
  void _onDeploymentCodeChanged(String value) {
    // Cancel previous timer
    _deploymentCodeTimer?.cancel();
    
    // Reset status if user cleared the field or changed to a different code
    if (value.trim() != _lastCheckedDeploymentCode) {
      setState(() {
        _isDeploymentCodeInUse = false;
        _isDeploymentCodeValid = false;
        _lastCheckedDeploymentCode = '';
        _deploymentCodeStatus = '';
      });
      
      // Clear any existing warning notifications
      ScaffoldMessenger.of(context).clearSnackBars();
    }
    
    // If field is empty, mark as invalid
    if (value.trim().isEmpty) {
      setState(() {
        _isDeploymentCodeValid = false;
        _deploymentCodeStatus = 'Deployment code required';
      });
      return;
    }
    
    // Basic format validation (you can customize this)
    if (value.trim().length < 3) {
      setState(() {
        _isDeploymentCodeValid = false;
        _deploymentCodeStatus = 'Code too short (minimum 3 characters)';
      });
      return;
    }
    
    // Debounce the API check
    _deploymentCodeTimer = Timer(const Duration(milliseconds: 1000), () {
      if (_deploymentCodeController.text.trim() == value.trim() && 
          value.trim().isNotEmpty && 
          _tokenController.text.trim().isNotEmpty) {
        _validateDeploymentCodeWithAPI(value.trim());
      }
    });
  }

  // ENHANCED: Comprehensive deployment code validation with API check
  Future<void> _validateDeploymentCodeWithAPI(String deploymentCode) async {
    if (_tokenController.text.trim().isEmpty) return; // Need token first
    
    setState(() {
      _isCheckingDeploymentCode = true;
      _deploymentCodeStatus = 'Validating deployment code...';
    });
    
    try {
      final checkResponse = await ApiService.checkStatus(
        _tokenController.text.trim(),
        deploymentCode,
      );

      if (checkResponse.success && checkResponse.data != null) {
        final isLoggedIn = checkResponse.data!['isLoggedIn'] ?? false;
        
        setState(() {
          _isDeploymentCodeInUse = isLoggedIn;
          _isDeploymentCodeValid = !isLoggedIn; // Valid if NOT in use
          _lastCheckedDeploymentCode = deploymentCode;
          
          if (isLoggedIn) {
            _deploymentCodeStatus = 'Code is in use on another device';
          } else {
            _deploymentCodeStatus = 'Code is available';
          }
        });
        
        if (isLoggedIn && mounted) {
          // Show PERSISTENT warning notification that doesn't auto-dismiss
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Container(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.block, color: Colors.white, size: 24),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '🚫 Deployment Code In Use',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'This code is active on another device. Login disabled until you use a different code.',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              backgroundColor: Colors.red[700],
              duration: Duration(days: 1), // Persistent - won't auto-dismiss
              behavior: SnackBarBehavior.fixed,
              dismissDirection: DismissDirection.none, // Cannot be swiped away
            ),
          );
        } else {
          // Code is available and valid
          ScaffoldMessenger.of(context).clearSnackBars();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text(
                      '✅ Valid deployment code',
                      style: TextStyle(fontSize: 14),
                    ),
                  ],
                ),
                backgroundColor: Colors.green[700],
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      } else {
        // API call failed or invalid response
        setState(() {
          _isDeploymentCodeValid = false;
          _deploymentCodeStatus = 'Unable to validate code';
        });
      }
    } catch (e) {
      // Network or other error
      print('Deployment code validation failed: $e');
      setState(() {
        _isDeploymentCodeValid = false;
        _deploymentCodeStatus = 'Validation failed - network error';
      });
    } finally {
      setState(() => _isCheckingDeploymentCode = false);
    }
  }

  // Check if login should be enabled
  bool get _canLogin {
    return _tokenController.text.trim().isNotEmpty &&
           _deploymentCodeController.text.trim().isNotEmpty &&
           _isDeploymentCodeValid &&
           !_isDeploymentCodeInUse &&
           !_isLoading &&
           !_isLocationChecking &&
           !_isCheckingDeploymentCode;
  }

  // ENHANCED: Login function with immediate aggressive sync
  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    
    // Double-check validation before proceeding
    if (!_canLogin) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please provide a valid deployment code that is not in use.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    setState(() => _isLoading = true);

    try {
      // Check location requirements first
      final hasLocationAccess = await _checkLocationRequirements();
      if (!hasLocationAccess) {
        setState(() => _isLoading = false);
        _showLocationRequirementDialog();
        return;
      }

      // Show login progress
      if (mounted) {
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
                Expanded(
                  child: Text(
                    '🔐 Logging in and starting sync...',
                    style: TextStyle(fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.blue[800],
            duration: Duration(seconds: 5),
          ),
        );
      }

      // Proceed with login attempt using authentication service
      final authResult = await _authService.login(
        _tokenController.text.trim(),
        _deploymentCodeController.text.trim(),
      );

      if (!mounted) return;

      // Clear any existing snackbars
      ScaffoldMessenger.of(context).clearSnackBars();

      if (authResult.isSuccess) {
        print('LoginScreen: Login successful (${authResult.isOffline ? "offline" : "online"}), starting sync...');
        
        // Check if we're in offline mode
        final isOffline = authResult.isOffline;
        
        // Save credentials immediately (for backward compatibility)
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', _tokenController.text.trim());
        await prefs.setString('deploymentCode', _deploymentCodeController.text.trim());
        await prefs.setBool('isTokenLocked', true);

        // NEW: Start aggressive sync immediately
        await _startImmediateAggressiveSync();
        
        // Start background service for continuous sync
        _startBackgroundServiceAfterLogin();
        _watchdogService.startWatchdog();

        // Show success and sync status
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isOffline 
                      ? '✅ Login successful (offline mode) - sync will start when online'
                      : '✅ Login successful! sync started - device online',
                    style: TextStyle(fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            backgroundColor: isOffline ? Colors.orange[800] : Colors.green[800],
            duration: Duration(seconds: 3),
          ),
        );

        // Small delay to show success message
        await Future.delayed(Duration(milliseconds: 1500));

        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (context) => DashboardScreen(
                token: _tokenController.text.trim(),
                deploymentCode: _deploymentCodeController.text.trim(),
              ),
            ),
            (route) => false,
          );
        }
      } else {
        print('LoginScreen: Login failed');
        
        // Enhanced error handling based on auth result
        String errorTitle = 'Login Failed';
        String errorMessage = authResult.errorMessage ?? 'Authentication failed. Please check your credentials and try again.';
        
        _showGenericLoginError(errorTitle, errorMessage);
      }
    } catch (e) {
      print('LoginScreen: Login error: $e');
      
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error, color: Colors.red, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '⌘ Connection error',
                    style: TextStyle(fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red[800],
            duration: Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // NEW: Start immediate aggressive sync to show device as online
  Future<void> _startImmediateAggressiveSync() async {
    try {
      print('LoginScreen: Starting immediate sync...');
      
      // Get current location immediately
      final position = await _locationService.getCurrentPosition(
        accuracy: LocationAccuracy.bestForNavigation,
        timeout: const Duration(seconds: 10),
      );

      if (position != null) {
        print('LoginScreen: Got location, sending immediate sync...');
        
        // Send location update immediately to show device as online
        final result = await ApiService.updateLocation(
          token: _tokenController.text.trim(),
          deploymentCode: _deploymentCodeController.text.trim(),
          position: position,
          batteryLevel: 100, // Default value for immediate sync
          signal: SignalStatus.strong,
        );

        if (result.success) {
          print('LoginScreen: ✅ Immediate sync successful - device should show as ONLINE');
        } else {
          print('LoginScreen: ❌ Immediate sync failed: ${result.message}');
        }

        // Send multiple rapid updates to ensure web app shows online status
        for (int i = 0; i < 3; i++) {
          await Future.delayed(Duration(seconds: 2));
          
          final rapidSync = await ApiService.updateLocation(
            token: _tokenController.text.trim(),
            deploymentCode: _deploymentCodeController.text.trim(),
            position: position,
            batteryLevel: 100,
            signal: SignalStatus.strong,
          );
          
          print('LoginScreen: Rapid sync ${i + 1}/3: ${rapidSync.success ? "✅" : "❌"}');
        }
        
      } else {
        print('LoginScreen: Could not get location for immediate sync');
        
        // Even without location, send a status update to show device as online
        try {
          // This won't work without a location, but we'll try background service
          print('LoginScreen: Starting background service for immediate sync...');
          await startBackgroundServiceSafely();
        } catch (e) {
          print('LoginScreen: Error starting background service: $e');
        }
      }
    } catch (e) {
      print('LoginScreen: Error in immediate sync: $e');
    }
  }

  Future<void> _showDuplicateLoginDialog(String message) async {
    // Implementation from previous code...
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.block, color: Colors.red, size: 32),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Login Blocked',
                style: TextStyle(color: Colors.red[700]),
              ),
            ),
          ],
        ),
        content: Text(message),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showGenericLoginError(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error, color: Colors.red, size: 28),
            SizedBox(width: 8),
            Expanded(child: Text(title)),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<bool> _checkLocationRequirements() async {
    setState(() => _isLocationChecking = true);
    final hasAccess = await _locationService.checkLocationRequirements();
    if (mounted) setState(() => _isLocationChecking = false);
    return hasAccess;
  }

  void _showLocationRequirementDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Location Required'),
        content: const Text('This app requires location access. Please enable it in your device settings.'),
        actions: [
          TextButton(
            child: const Text('OK'),
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (context) => const LocationScreen()));
            },
          ),
        ],
      ),
    );
  }

  Future<void> _startBackgroundServiceAfterLogin() async {
    try {
      await startBackgroundServiceSafely();
    } catch (e) {
      print("Error starting background service: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    // Get screen dimensions for responsive sizing
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;
    final isTablet = screenWidth > 600;
    final isSmallScreen = screenHeight < 700;
    
    // Calculate responsive values
    final logoHeight = isTablet ? 140.0 : (isSmallScreen ? 80.0 : 120.0);
    final horizontalPadding = screenWidth * 0.08; // 8% of screen width
    final titleFontSize = isTablet ? 32.0 : (isSmallScreen ? 20.0 : 24.0);
    final buttonHeight = isTablet ? 60.0 : (isSmallScreen ? 45.0 : 50.0);
    final buttonFontSize = isTablet ? 20.0 : (isSmallScreen ? 16.0 : 18.0);
    final iconSize = isTablet ? 28.0 : (isSmallScreen ? 20.0 : 24.0);
    final spacingLarge = isTablet ? 40.0 : (isSmallScreen ? 20.0 : 32.0);
    final spacingMedium = isTablet ? 30.0 : (isSmallScreen ? 16.0 : 24.0);
    final spacingSmall = isTablet ? 24.0 : (isSmallScreen ? 12.0 : 16.0);

    return Scaffold(
      appBar: AppBar(
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            AppConstants.appTitle,
            style: TextStyle(fontSize: isTablet ? 22.0 : 18.0),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.system_update,
              size: isTablet ? 28.0 : 24.0,
            ),
            onPressed: _checkForUpdates,
            tooltip: 'Check for Updates',
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: 16.0,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: screenHeight - kToolbarHeight - MediaQuery.of(context).padding.top - 32,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo section with responsive sizing
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Image.asset(
                          'assets/images/pnp_logo.png',
                          height: logoHeight,
                          fit: BoxFit.contain,
                        ),
                      ),
                      SizedBox(width: screenWidth * 0.04), // 4% of screen width
                      Flexible(
                        child: Image.asset(
                          'assets/images/images.png',
                          height: logoHeight,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: spacingMedium),
                  
                  // Title with responsive font size
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Secure Access',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontSize: titleFontSize,
                      ),
                    ),
                  ),
                  SizedBox(height: spacingLarge),
                  
                  // Token field with responsive icons
                  TextFormField(
                    controller: _tokenController,
                    readOnly: _isTokenLocked,
                    style: TextStyle(fontSize: isTablet ? 18.0 : 16.0),
                    decoration: InputDecoration(
                      labelText: 'Token',
                      labelStyle: TextStyle(fontSize: isTablet ? 18.0 : 16.0),
                      prefixIcon: Icon(Icons.vpn_key, size: iconSize),
                      suffixIcon: _isTokenLocked
                          ? Icon(Icons.lock, color: Colors.grey, size: iconSize)
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.upload_file, size: iconSize),
                                  onPressed: _uploadTokenFile,
                                  tooltip: 'Upload Token from .txt file',
                                ),
                                IconButton(
                                  icon: Icon(Icons.qr_code_scanner, size: iconSize),
                                  onPressed: _scanQRCodeForToken,
                                  tooltip: 'Scan QR Code',
                                ),
                              ],
                            ),
                      border: const OutlineInputBorder(),
                      fillColor: _isTokenLocked ? Colors.grey[200] : null,
                      filled: _isTokenLocked,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: isTablet ? 20.0 : 16.0,
                      ),
                    ),
                    validator: (value) => value!.isEmpty ? 'Please enter a token' : null,
                  ),
                  SizedBox(height: spacingSmall),

                  // ENHANCED: Deployment code field with comprehensive validation UI
                  TextFormField(
                    controller: _deploymentCodeController,
                    obscureText: !_isDeploymentCodeVisible,
                    onChanged: _onDeploymentCodeChanged,
                    style: TextStyle(fontSize: isTablet ? 18.0 : 16.0),
                    decoration: InputDecoration(
                      labelText: 'Deployment Code',
                      labelStyle: TextStyle(fontSize: isTablet ? 18.0 : 16.0),
                      prefixIcon: Icon(
                        _isDeploymentCodeInUse 
                            ? Icons.block 
                            : (_isDeploymentCodeValid ? Icons.verified : Icons.shield), 
                        size: iconSize,
                        color: _isDeploymentCodeInUse 
                            ? Colors.red 
                            : (_isDeploymentCodeValid ? Colors.green : null),
                      ),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Show checking indicator
                          if (_isCheckingDeploymentCode)
                            Container(
                              width: 20,
                              height: 20,
                              margin: EdgeInsets.only(right: 8),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                              ),
                            ),
                          // Show status indicator
                          if (!_isCheckingDeploymentCode && _lastCheckedDeploymentCode.isNotEmpty)
                            Container(
                              margin: EdgeInsets.only(right: 8),
                              child: Icon(
                                _isDeploymentCodeInUse 
                                    ? Icons.error 
                                    : (_isDeploymentCodeValid ? Icons.check_circle : Icons.warning),
                                color: _isDeploymentCodeInUse 
                                    ? Colors.red 
                                    : (_isDeploymentCodeValid ? Colors.green : Colors.orange),
                                size: 20,
                              ),
                            ),
                          IconButton(
                            icon: Icon(Icons.qr_code_scanner, size: iconSize),
                            onPressed: _scanQRCodeForDeployment,
                            tooltip: 'Scan Deployment Code',
                          ),
                          IconButton(
                            icon: Icon(
                              _isDeploymentCodeVisible ? Icons.visibility : Icons.visibility_off,
                              size: iconSize,
                            ),
                            onPressed: () => setState(() => _isDeploymentCodeVisible = !_isDeploymentCodeVisible),
                          ),
                        ],
                      ),
                      border: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: _isDeploymentCodeInUse 
                              ? Colors.red 
                              : (_isDeploymentCodeValid ? Colors.green : Colors.grey),
                          width: (_isDeploymentCodeInUse || _isDeploymentCodeValid) ? 2.0 : 1.0,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: _isDeploymentCodeInUse 
                              ? Colors.red 
                              : (_isDeploymentCodeValid ? Colors.green : Colors.grey),
                          width: (_isDeploymentCodeInUse || _isDeploymentCodeValid) ? 2.0 : 1.0,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: _isDeploymentCodeInUse 
                              ? Colors.red 
                              : (_isDeploymentCodeValid ? Colors.green : Colors.blue),
                          width: 2.0,
                        ),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: isTablet ? 20.0 : 16.0,
                      ),
                      // Show helper text for status
                      helperText: _deploymentCodeStatus.isNotEmpty ? _deploymentCodeStatus : null,
                      helperStyle: TextStyle(
                        color: _isDeploymentCodeInUse 
                            ? Colors.red 
                            : (_isDeploymentCodeValid ? Colors.green : Colors.orange),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    validator: (value) => value!.isEmpty ? 'Please enter a deployment code' : null,
                  ),
                  SizedBox(height: spacingMedium),

                  // ENHANCED: Secure Login button with validation-based enable/disable (rocket icon removed)
                  SizedBox(
                    width: double.infinity,
                    height: buttonHeight,
                    child: ElevatedButton(
                      onPressed: _canLogin ? _login : null,
                      style: ElevatedButton.styleFrom(
                        textStyle: TextStyle(
                          fontSize: buttonFontSize,
                          fontWeight: FontWeight.bold,
                        ),
                        backgroundColor: _canLogin 
                            ? Theme.of(context).colorScheme.primary 
                            : Colors.grey[400],
                        foregroundColor: _canLogin 
                            ? Colors.white 
                            : Colors.grey[600],
                        elevation: _canLogin ? 4.0 : 0.0,
                      ),
                      child: (_isLoading || _isLocationChecking || _isCheckingDeploymentCode)
                          ? SizedBox(
                              width: iconSize,
                              height: iconSize,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (!_canLogin && !_isLoading && !_isLocationChecking && !_isCheckingDeploymentCode) ...[
                                    Icon(Icons.lock, size: iconSize * 0.8),
                                    SizedBox(width: 8),
                                  ],
                                  Text(
                                    _canLogin ? 'Secure Login' : 'Login Disabled',
                                    style: TextStyle(fontSize: buttonFontSize),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),
                  SizedBox(height: spacingMedium),

                  // NEW: FAQ and Feedback buttons (non-functional)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: null, // Non-functional as requested
                          icon: Icon(Icons.help_outline, size: iconSize * 0.8),
                          label: Text(
                            'FAQ',
                            style: TextStyle(fontSize: buttonFontSize * 0.8),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.symmetric(vertical: buttonHeight * 0.3),
                            side: BorderSide(color: Colors.grey[400]!),
                            foregroundColor: Colors.grey[600],
                          ),
                        ),
                      ),
                      SizedBox(width: spacingSmall),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: null, // Non-functional as requested
                          icon: Icon(Icons.feedback_outlined, size: iconSize * 0.8),
                          label: Text(
                            'Feedback',
                            style: TextStyle(fontSize: buttonFontSize * 0.8),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.symmetric(vertical: buttonHeight * 0.3),
                            side: BorderSide(color: Colors.grey[400]!),
                            foregroundColor: Colors.grey[600],
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: spacingSmall),
                  
                  // Version text and status with responsive sizing (Login requirements card removed)
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      children: [
                        Text(
                          'v$_appVersion • Real-time Session Monitoring • Aggressive Sync',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: isTablet ? 16.0 : 14.0,
                          ),
                        ),
                        if (!_canLogin && _deploymentCodeController.text.trim().isNotEmpty) ...[
                          SizedBox(height: 8),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.orange.withOpacity(0.3)),
                            ),
                            child: Text(
                              _isCheckingDeploymentCode 
                                  ? '⏳ Validating deployment code...'
                                  : (_isDeploymentCodeInUse 
                                      ? '🚫 Login blocked - code in use' 
                                      : '⚠️ Please wait for validation'),
                              style: TextStyle(
                                color: Colors.orange[700],
                                fontSize: isTablet ? 14.0 : 12.0,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Helper method to build requirement rows - REMOVED since Login Requirements card is removed
  // Widget _buildRequirementRow(String text, bool satisfied) { ... }

  // Check for app updates
  Future<void> _checkForUpdates() async {
    try {
      // Show loading indicator
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

      // Clear any existing snackbars
      ScaffoldMessenger.of(context).clearSnackBars();

      if (result.hasUpdate && result.updateInfo != null) {
        // Show update dialog
        showDialog(
          context: context,
          builder: (context) => UpdateDialog(
            updateInfo: result.updateInfo!,
            currentVersion: result.currentVersion,
          ),
        );
      } else if (result.error != null) {
        // Show error message
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
        // No update available
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
      // Clear any existing snackbars
      ScaffoldMessenger.of(context).clearSnackBars();
      
      // Show error message
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