import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/location_service.dart';
import '../services/api_service.dart';
import '../services/background_service.dart';
import '../services/watchdog_service.dart';
import '../utils/constants.dart';
import 'dashboard_screen.dart';
import 'location_screen.dart';
import 'qr_view_screen.dart';

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

  bool _isTokenLocked = false; // controls locking state
  bool _isLoading = false;
  bool _isLocationChecking = false;
  String _appVersion = '';
  bool _hasStoredCredentials = false;
  bool _hasStoredQRCode = false;

  @override
  void initState() {
    super.initState();
    print('LoginScreen: initState called');
    _initializeScreen();
  }

  @override
  void dispose() {
    print('LoginScreen: dispose called');
    _tokenController.dispose();
    _deploymentCodeController.dispose();
    super.dispose();
  }

  // Initialize screen with stored credentials check
  Future<void> _initializeScreen() async {
    await _getAppVersion();
    await _loadStoredCredentials(); // 🔒 will also load lock state
    await _initializeWatchdog();
  }

  Future<void> _getAppVersion() async {
    try {
      print('LoginScreen: Getting app version...');
      final packageInfo = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _appVersion = packageInfo.version);
        print('LoginScreen: App version retrieved: $_appVersion');
      }
    } catch (e) {
      print('LoginScreen: Error getting app version: $e');
      if (mounted) {
        setState(() => _appVersion = '1.0.0');
      }
    }
  }

  // Load stored credentials and QR code
  Future<void> _loadStoredCredentials() async {
    try {
      print('LoginScreen: Loading stored credentials...');
      final prefs = await SharedPreferences.getInstance();
      final storedToken = prefs.getString('token');
      final storedDeploymentCode = prefs.getString('deploymentCode');
      final storedQRCode = prefs.getString('qr_code'); // Load stored QR code
      final storedLockState =
          prefs.getBool('isTokenLocked') ?? false; // 🔒 load

      if (mounted) {
        setState(() {
          _isTokenLocked = storedLockState; // 🔒 restore lock state
        });
      }
      if (mounted) {
        setState(() {
          _isTokenLocked = storedLockState; // 🔒 restore lock state
        });
      }

      if (storedToken != null && storedDeploymentCode != null) {
        print('LoginScreen: Found stored credentials');
        if (mounted) {
          setState(() {
            _tokenController.text = storedToken;
            _deploymentCodeController.text = storedDeploymentCode;
            _hasStoredCredentials = true;
            _hasStoredQRCode = storedQRCode != null;
          });
        }
      } else {
        print('LoginScreen: No stored credentials found');

        // Even if no credentials, check if we have a stored QR code
        if (storedQRCode != null) {
          print('LoginScreen: Found stored QR code');
          if (mounted) {
            setState(() {
              _tokenController.text = storedQRCode;
              _hasStoredQRCode = true;
            });
          }
        }
      }
    } catch (e) {
      print('LoginScreen: Error loading stored credentials: $e');
    }
  }

  // Initialize watchdog service
  Future<void> _initializeWatchdog() async {
    try {
      await _watchdogService.initialize();
      await _watchdogService.markAppAsAlive();

      // Check if app was previously dead
      final wasAppDead = await _watchdogService.wasAppDead();
      if (wasAppDead && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'App monitoring was interrupted. Please login to resume tracking.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      print('LoginScreen: Error initializing watchdog: $e');
    }
  }

  Future<void> _scanQRCode() async {
    try {
      print('LoginScreen: Starting QR scan...');
      final scannedCode = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (context) => const QRScannerScreen()),
      );

      if (scannedCode != null && mounted) {
        print(
            'LoginScreen: QR code scanned: ${scannedCode.substring(0, 10)}...');
        setState(() {
          _tokenController.text = scannedCode;
          _hasStoredQRCode = false; // Mark as newly scanned
        });

        // Save the new QR code immediately
        await _saveQRCode(scannedCode);
      }
    } catch (e) {
      print('LoginScreen: Error scanning QR code: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to scan QR code: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Save QR code to persistent storage
  Future<void> _saveQRCode(String qrCode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('qr_code', qrCode);
      print('LoginScreen: QR code saved successfully');

      if (mounted) {
        setState(() => _hasStoredQRCode = true);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('QR code saved for future use'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('LoginScreen: Error saving QR code: $e');
    }
  }

  // Load stored QR code
  Future<void> _loadStoredQRCode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedQRCode = prefs.getString('qr_code');

      if (storedQRCode != null && mounted) {
        setState(() {
          _tokenController.text = storedQRCode;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Stored QR code loaded'),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 2),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No stored QR code found'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('LoginScreen: Error loading stored QR code: $e');
    }
  }

  // Clear stored QR code
  Future<void> _clearStoredQRCode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('qr_code');

      if (mounted) {
        setState(() {
          _tokenController.clear();
          _hasStoredQRCode = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Stored QR code cleared'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('LoginScreen: Error clearing stored QR code: $e');
    }
  }

  Future<bool> _checkLocationRequirements() async {
    if (!mounted) return false;

    print('LoginScreen: Checking location requirements...');
    setState(() => _isLocationChecking = true);

    try {
      final hasAccess = await _locationService.checkLocationRequirements();
      print('LoginScreen: Location access: $hasAccess');
      if (mounted) {
        setState(() => _isLocationChecking = false);
      }
      return hasAccess;
    } catch (e) {
      print('LoginScreen: Error checking location requirements: $e');
      if (mounted) {
        setState(() => _isLocationChecking = false);
      }
      return false;
    }
  }

  void _showLocationRequirementDialog() {
    if (!mounted) return;

    print('LoginScreen: Showing location requirement dialog');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.location_off, color: Colors.red, size: 24),
            const SizedBox(width: 8),
            const Text('Location Required'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This app requires location access to function properly.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Text('Please ensure:'),
            SizedBox(height: 8),
            Text('• Location permission is granted'),
            Text('• Location services are enabled on your device'),
            SizedBox(height: 12),
            Text(
              'You cannot login without enabling location access.',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _navigateToLocationSetup();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.tealAccent,
              foregroundColor: Colors.black,
            ),
            child: const Text('Setup Location'),
          ),
        ],
      ),
    );
  }

  void _navigateToLocationSetup() {
    if (!mounted) return;

    print('LoginScreen: Navigating to location setup');
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const LocationScreen()),
    );
  }

  Future<void> _startBackgroundServiceAfterLogin() async {
    try {
      print(
          'LoginScreen: Starting background service after successful login...');

      // Start background service with a small delay to ensure app is stable
      await Future.delayed(const Duration(milliseconds: 500));

      final started = await startBackgroundServiceSafely();
      print('LoginScreen: Background service start result: $started');

      if (started && mounted) {
        // Show a brief success message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Background monitoring enabled ✓'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('LoginScreen: Error starting background service: $e');
      // Don't show error to user - app should continue working even without background service
    }
  }

  Future<void> _login() async {
    if (!mounted || !_formKey.currentState!.validate()) return;

    print('LoginScreen: Starting login process...');
    setState(() => _isLoading = true);

    try {
      // Step 1: Check location requirements
      print('LoginScreen: Step 1 - Checking location...');
      final hasLocationAccess = await _checkLocationRequirements();
      if (!hasLocationAccess) {
        print('LoginScreen: Location access denied');
        if (mounted) {
          setState(() => _isLoading = false);
          _showLocationRequirementDialog();
        }
        return;
      }
      print('LoginScreen: Location access granted');

      // Step 2: Perform API login
      print('LoginScreen: Step 2 - Performing API login...');
      final response = await ApiService.login(
        _tokenController.text.trim(),
        _deploymentCodeController.text.trim(),
      );
      print(
          'LoginScreen: API response received - success: ${response.success}');

      if (!mounted) {
        print('LoginScreen: Widget not mounted after API call');
        return;
      }

      if (response.success) {
        print('LoginScreen: Login successful, saving credentials...');

        // Step 3: Save credentials and QR code
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('token', _tokenController.text.trim());
          await prefs.setString(
              'deploymentCode', _deploymentCodeController.text.trim());

          // Save QR code if it's not already stored or if it's new
          if (!_hasStoredQRCode || _tokenController.text.trim().isNotEmpty) {
            await prefs.setString('qr_code', _tokenController.text.trim());
            print('LoginScreen: QR code saved with credentials');
          }

          print('LoginScreen: Credentials saved successfully');

          // 🔒 Step 3.5: Lock the token field after successful login
          setState(() {
            _isTokenLocked = true;
          });
          print('LoginScreen: Token field locked after login');

          // Step 4: Start background service and watchdog
          _startBackgroundServiceAfterLogin(); // Don't await - let it run in background
          _watchdogService.startWatchdog(); // Start monitoring

          // Step 5: Navigate to dashboard
          print('LoginScreen: Navigating to dashboard...');

          // Add a small delay to ensure everything is saved
          await Future.delayed(const Duration(milliseconds: 200));

          if (mounted) {
            print('LoginScreen: About to navigate to DashboardScreen');

            // Use pushAndRemoveUntil to prevent back navigation
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder: (context) {
                  print('LoginScreen: Building DashboardScreen...');
                  return DashboardScreen(
                    token: _tokenController.text.trim(),
                    deploymentCode: _deploymentCodeController.text.trim(),
                  );
                },
              ),
              (route) => false, // Remove all previous routes
            );

            print('LoginScreen: Navigation completed');
          } else {
            print('LoginScreen: Widget not mounted, cannot navigate');
          }
        } catch (e) {
          print('LoginScreen: Error saving credentials or navigating: $e');
          print('LoginScreen: Stack trace: ${StackTrace.current}');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error saving login data: ${e.toString()}'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } else {
        print('LoginScreen: Login failed - ${response.message}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      print('LoginScreen: Login error: $e');
      print('LoginScreen: Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Login failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      print('LoginScreen: Login process completed');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    print('LoginScreen: Building UI');

    // Disable back button navigation
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(AppConstants.appTitle),
          elevation: 0,
          backgroundColor: AppColors.primaryRed,
          foregroundColor: Colors.white,
          automaticallyImplyLeading: false, // Remove back button
        ),
        body: GestureDetector(
          // Handle swipe left gesture as home button
          onPanUpdate: (details) {
            if (details.delta.dx > 20) {
              // Swipe right detected - simulate home button
              SystemNavigator.pop();
            }
          },
          child: SingleChildScrollView(
            reverse: true,
            padding: const EdgeInsets.all(32),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.02),

                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.primaryRed.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: AppColors.primaryRed.withOpacity(0.3)),
                    ),
                    child: Column(
                      children: [
                        Image.asset(
                          'assets/images/pnp_logo.png',
                          width: 120,
                          height: 120,
                          errorBuilder: (context, error, stackTrace) {
                            print('LoginScreen: Error loading logo: $error');
                            return Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                color: AppColors.primaryRed.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(60),
                              ),
                              child: const Icon(
                                Icons.shield,
                                size: 60,
                                color: AppColors.primaryRed,
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        Text(
                          AppConstants.appTitle.toUpperCase(),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryRed,
                            letterSpacing: 1.2,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.primaryGreen,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            AppConstants.appMotto,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 0.8,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  Text(
                    'Secure Access Required',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryRed,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _hasStoredCredentials
                        ? 'Credentials loaded from previous session'
                        : 'Enter your authentication credentials',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: _hasStoredCredentials
                              ? Colors.green[400]
                              : Colors.grey[400],
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  TextFormField(
                    controller: _tokenController,
                    readOnly: _tokenController
                        .text.isNotEmpty, // 🔒 auto-lock if token exists
                    decoration: InputDecoration(
                      labelText: 'Token',
                      hintText: 'Input your token here',
                      prefixIcon:
                          Icon(Icons.vpn_key, color: AppColors.primaryRed),
                      suffixIcon: IconButton(
                        icon: Icon(Icons.qr_code_scanner,
                            color: AppColors.primaryRed),
                        onPressed: _tokenController.text.isEmpty
                            ? _scanQRCode
                            : null, // disabled if locked
                        tooltip: 'Scan QR code',
                      ),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            BorderSide(color: AppColors.primaryRed, width: 2),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please input your token';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _deploymentCodeController,
                    decoration: InputDecoration(
                      labelText: 'Deployment Code',
                      hintText: 'Enter your deployment code or Scan QR Code',
                      prefixIcon:
                          Icon(Icons.badge, color: AppColors.primaryRed),
                      suffixIcon: IconButton(
                        icon: Icon(Icons.qr_code_scanner,
                            color: AppColors.primaryRed),
                        onPressed: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => QRViewScreen(),
                            ),
                          );
                          if (result != null) {
                            setState(() {
                              _deploymentCodeController.text = result;
                            });
                          }
                        },
                      ),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            BorderSide(color: AppColors.primaryRed, width: 2),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your deployment code';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed:
                          (_isLoading || _isLocationChecking) ? null : _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryRed,
                        foregroundColor: Colors.white,
                      ),
                      child: _isLoading || _isLocationChecking
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(_isLocationChecking
                                    ? 'Checking Location...'
                                    : 'Authenticating...'),
                              ],
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.login),
                                SizedBox(width: 8),
                                Text(
                                  'Secure Login',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Show stored credentials/QR code info
                  if (_hasStoredCredentials || _hasStoredQRCode) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green[900]?.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle,
                              color: Colors.green, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _hasStoredCredentials
                                  ? 'Previous login credentials loaded automatically'
                                  : 'Stored QR code available - tap history icon to load',
                              style: TextStyle(
                                color: Colors.green[100],
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[900]?.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            color: Colors.lightBlueAccent, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Contact your administrator if you don\'t have a token or deployment code',
                            style: TextStyle(
                              color: Colors.lightBlueAccent[100],
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: MediaQuery.of(context).size.height * 0.02),

                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[900]?.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[700]!),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.copyright,
                                color: Colors.grey[400], size: 16),
                            const SizedBox(width: 8),
                            Text(
                              '2025 Philippine National Police',
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.primaryRed.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: AppColors.primaryRed.withOpacity(0.3)),
                          ),
                          child: Text(
                            AppConstants.developerCredit,
                            style: TextStyle(
                              color: Colors.red[300],
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),
                  Text(
                    'v$_appVersion',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
