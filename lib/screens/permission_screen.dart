import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../widgets/permission_status_widget.dart';
import '../services/permission_service.dart';
import 'login_screen.dart';

class PermissionScreen extends StatefulWidget {
  const PermissionScreen({super.key});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen> {
  final _permissionService = PermissionService();

  Map<String, bool> _permissions = {
    'location': false,
    'locationAlways': false,
    'camera': false,
    'notification': false,
    'ignoreBatteryOptimizations': false,
    'scheduleExactAlarm': false,
  };
  bool _isLoading = false;
  Map<String, bool> _requestingPermissions = {};

  @override
  void initState() {
    super.initState();
    _checkAllPermissions();
  }

  Future<void> _checkAllPermissions() async {
    setState(() => _isLoading = true);

    try {
      final permissions = await _permissionService.checkAllPermissions();
      if (mounted) {
        setState(() {
          _permissions = permissions;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('PermissionScreen: Error checking permissions: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _requestAllPermissions() async {
    setState(() => _isLoading = true);

    try {
      print('PermissionScreen: Starting permission request flow...');
      
      // Request standard permissions first
      await _requestSpecificPermission('location');
      await _requestSpecificPermission('camera');
      await _requestSpecificPermission('notification');
      await _requestSpecificPermission('scheduleExactAlarm');

      // Request critical permissions
      await _requestSpecificPermission('locationAlways');
      await _requestSpecificPermission('ignoreBatteryOptimizations');

      // Final check
      await _checkAllPermissions();

    } catch (e) {
      print('PermissionScreen: Error requesting permissions: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // FIXED: Request specific permission with proper error handling
  Future<void> _requestSpecificPermission(String permissionType) async {
    if (_requestingPermissions[permissionType] == true) {
      print('PermissionScreen: Already requesting $permissionType, skipping...');
      return;
    }

    setState(() {
      _requestingPermissions[permissionType] = true;
    });

    try {
      print('PermissionScreen: Requesting $permissionType permission...');
      
      bool result = false;
      Permission? permission = _getPermissionFromType(permissionType);
      
      if (permission != null) {
        // Show loading indicator
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  ),
                  SizedBox(width: 12),
                  Text('Requesting $permissionType permission...'),
                ],
              ),
              duration: Duration(seconds: 3),
              backgroundColor: Colors.blue[700],
            ),
          );
        }

        // Request the permission
        result = await _permissionService.requestPermission(permission);
        
        // Clear the loading snackbar
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
        }
      }

      if (mounted) {
        setState(() {
          _permissions[permissionType] = result;
        });

        // Show result feedback
        final message = result 
            ? '✅ ${_getPermissionDisplayName(permissionType)} granted'
            : '❌ ${_getPermissionDisplayName(permissionType)} denied';
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: result ? Colors.green[700] : Colors.orange[700],
            duration: Duration(seconds: 2),
          ),
        );

        // If denied and it's a critical permission, show guidance
        if (!result && _isCriticalPermission(permissionType)) {
          await Future.delayed(Duration(seconds: 2));
          
          if (permission != null) {
            final status = await permission.status;
            if (status.isPermanentlyDenied) {
              await _permissionService.showPermissionRationale(context, permissionType);
            } else if (permissionType == 'locationAlways') {
              await _showBackgroundLocationGuidance();
            }
          }
        }
      }
    } catch (e) {
      print('PermissionScreen: Error requesting $permissionType permission: $e');
      
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('❌ Error requesting ${_getPermissionDisplayName(permissionType)}'),
                Text('${e.toString()}', style: TextStyle(fontSize: 12)),
              ],
            ),
            backgroundColor: Colors.red[700],
            duration: Duration(seconds: 4),
          ),
        );
      }
    } finally {
      setState(() {
        _requestingPermissions[permissionType] = false;
      });
    }
  }

  // Show specific guidance for background location
  Future<void> _showBackgroundLocationGuidance() async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.location_on, color: Colors.orange, size: 28),
            SizedBox(width: 12),
            Expanded(child: Text('Background Location Guide')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Important Steps:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '1. First grant "While using app" location\n'
                      '2. Then grant "Allow all the time"\n'
                      '3. Select "Allow all the time" when prompted\n'
                      '4. If settings open, find Location permissions\n'
                      '5. Set to "Allow all the time"',
                      style: TextStyle(height: 1.4),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16),
              Text(
                'This is required for 24/7 location monitoring when the app is in the background.',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('I Understand'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _requestSpecificPermission('locationAlways');
            },
            child: Text('Try Again'),
          ),
        ],
      ),
    );
  }

  // Helper methods
  Permission? _getPermissionFromType(String permissionType) {
    switch (permissionType) {
      case 'location': return Permission.location;
      case 'locationAlways': return Permission.locationAlways;
      case 'camera': return Permission.camera;
      case 'notification': return Permission.notification;
      case 'ignoreBatteryOptimizations': return Permission.ignoreBatteryOptimizations;
      case 'scheduleExactAlarm': return Permission.scheduleExactAlarm;
      default: return null;
    }
  }

  String _getPermissionDisplayName(String permissionType) {
    switch (permissionType) {
      case 'location': return 'Location';
      case 'locationAlways': return 'Background Location';
      case 'camera': return 'Camera';
      case 'notification': return 'Notification';
      case 'ignoreBatteryOptimizations': return 'Battery Optimization';
      case 'scheduleExactAlarm': return 'Exact Alarm';
      default: return permissionType;
    }
  }

  bool _isCriticalPermission(String permissionType) {
    return ['location', 'locationAlways', 'notification', 'ignoreBatteryOptimizations'].contains(permissionType);
  }

  bool get _canProceed =>
      _permissions['location']! &&
      _permissions['locationAlways']! &&
      _permissions['notification']! &&
      _permissions['ignoreBatteryOptimizations']!;

  @override
  Widget build(BuildContext context) {
    // Get screen dimensions for responsive design
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;
    final isTablet = screenWidth > 600;
    final isSmallScreen = screenHeight < 700;
    
    // Calculate responsive values
    final horizontalPadding = screenWidth * 0.05; // 5% of screen width
    final titleFontSize = isTablet ? 32.0 : (isSmallScreen ? 22.0 : 28.0);
    final subtitleFontSize = isTablet ? 18.0 : (isSmallScreen ? 14.0 : 16.0);
    final buttonHeight = isTablet ? 64.0 : (isSmallScreen ? 48.0 : 56.0);
    final buttonFontSize = isTablet ? 20.0 : (isSmallScreen ? 16.0 : 18.0);
    final spacingLarge = isTablet ? 48.0 : (isSmallScreen ? 24.0 : 32.0);
    final spacingMedium = isTablet ? 32.0 : (isSmallScreen ? 16.0 : 24.0);
    final spacingSmall = isTablet ? 16.0 : (isSmallScreen ? 8.0 : 12.0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('App Permissions'),
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _checkAllPermissions,
            tooltip: 'Refresh Status',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: spacingMedium,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // FIXED: Header section with proper alignment
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Critical Permissions Required',
                          style: TextStyle(
                            fontSize: titleFontSize,
                            fontWeight: FontWeight.bold,
                            height: 1.1,
                          ),
                        ),
                        SizedBox(height: spacingSmall),
                        Text(
                          'Please grant the following permissions for full functionality.',
                          style: TextStyle(
                            fontSize: subtitleFontSize,
                            color: Colors.grey[600],
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: spacingLarge),

                    // FIXED: Permission cards with consistent spacing and alignment
                    Column(
                      children: [
                        // Background Location Permission - MOST CRITICAL
                        PermissionStatusWidget(
                          status: _permissions['locationAlways']!
                              ? PermissionStatus.granted
                              : PermissionStatus.denied,
                          title: 'Background Location (24/7)',
                          description:
                              'CRITICAL: Required for continuous location tracking. Select "Allow all the time" when prompted.',
                          onRequest: _requestingPermissions['locationAlways'] == true
                              ? null
                              : () => _requestSpecificPermission('locationAlways'),
                        ),
                        SizedBox(height: spacingSmall),

                        // Battery Optimization
                        PermissionStatusWidget(
                          status: _permissions['ignoreBatteryOptimizations']!
                              ? PermissionStatus.granted
                              : PermissionStatus.denied,
                          title: 'Battery Optimization',
                          description:
                              'CRITICAL: Required for 24/7 background monitoring. Please select "Allow".',
                          onRequest: _requestingPermissions['ignoreBatteryOptimizations'] == true
                              ? null
                              : () => _requestSpecificPermission('ignoreBatteryOptimizations'),
                        ),
                        SizedBox(height: spacingSmall),

                        // Basic Location Permission
                        PermissionStatusWidget(
                          status: _permissions['location']!
                              ? PermissionStatus.granted
                              : PermissionStatus.denied,
                          title: 'Location Permission',
                          description:
                              'CRITICAL: Required for GPS tracking and position monitoring.',
                          onRequest: _requestingPermissions['location'] == true
                              ? null
                              : () => _requestSpecificPermission('location'),
                        ),
                        SizedBox(height: spacingSmall),

                        // Notification Permission
                        PermissionStatusWidget(
                          status: _permissions['notification']!
                              ? PermissionStatus.granted
                              : PermissionStatus.denied,
                          title: 'Notification Permission',
                          description:
                              'CRITICAL: Essential for background service alerts.',
                          onRequest: _requestingPermissions['notification'] == true
                              ? null
                              : () => _requestSpecificPermission('notification'),
                        ),
                        SizedBox(height: spacingSmall),

                        // Schedule Exact Alarm (Android 12+)
                        PermissionStatusWidget(
                          status: _permissions['scheduleExactAlarm']!
                              ? PermissionStatus.granted
                              : PermissionStatus.denied,
                          title: 'Schedule Exact Alarm',
                          description:
                              'RECOMMENDED: For precise timing on Android 12+.',
                          onRequest: _requestingPermissions['scheduleExactAlarm'] == true
                              ? null
                              : () => _requestSpecificPermission('scheduleExactAlarm'),
                        ),
                        SizedBox(height: spacingSmall),

                        // Camera Permission
                        PermissionStatusWidget(
                          status: _permissions['camera']!
                              ? PermissionStatus.granted
                              : PermissionStatus.denied,
                          title: 'Camera Permission',
                          description:
                              'OPTIONAL: Used for QR code scanning for easier login.',
                          onRequest: _requestingPermissions['camera'] == true
                              ? null
                              : () => _requestSpecificPermission('camera'),
                        ),
                      ],
                    ),
                    SizedBox(height: spacingLarge),

                    // FIXED: Action buttons with consistent alignment
                    Column(
                      children: [
                        // Grant All Button
                        SizedBox(
                          width: double.infinity,
                          height: buttonHeight,
                          child: ElevatedButton.icon(
                            onPressed: _isLoading ? null : _requestAllPermissions,
                            icon: _isLoading
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2),
                                  )
                                : const Icon(Icons.security),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                _isLoading ? 'Requesting...' : 'Request All Permissions',
                                style: TextStyle(
                                  fontSize: buttonFontSize,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: spacingSmall),

                        // Continue Button
                        SizedBox(
                          width: double.infinity,
                          height: buttonHeight,
                          child: ElevatedButton.icon(
                            onPressed: _canProceed
                                ? () => Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => const LoginScreen(),
                                      ),
                                    )
                                : null,
                            icon: Icon(
                              _canProceed ? Icons.login : Icons.lock,
                            ),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                _canProceed
                                    ? 'Continue to Login'
                                    : 'Critical Permissions Required',
                                style: TextStyle(
                                  fontSize: buttonFontSize,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _canProceed ? Colors.green : Colors.grey[400],
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    
                    // Bottom spacing for scroll comfort
                    SizedBox(height: spacingMedium),
                  ],
                ),
              ),
            ),
    );
  }
}