import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:project_nexusv2/services/background_service.dart';
import 'package:project_nexusv2/services/permission_service.dart';
import 'screens/permission_screen.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'utils/constants.dart';

Future<void> main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    print('Main: Flutter initialized');

    // This is intentionally not awaited to avoid blocking the UI thread.
    // Any errors during background service initialization will be handled
    // within the function itself and will not crash the app. //ignore
    _initializeBackgroundServiceAsync();

    print('Main: Starting app...');
    runApp(const MyApp());
  } catch (e, stackTrace) {
    print('Main: Error in main: $e');
    print('Main: Stack trace: $stackTrace');
    // Still try to run the app
    runApp(const MyApp());
  }
}

// Initialize background service asynchronously without blocking app startup
void _initializeBackgroundServiceAsync() {
  Future.delayed(const Duration(milliseconds: 500), () async {
    try {
      print('Main: Initializing background service asynchronously...');
      await initializeService();
      print('Main: Background service initialization completed');
    } catch (e) {
      print('Main: Background service initialization failed: $e');
      // App continues normally even if background service fails
    }
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    print('MyApp: Building MaterialApp');

    return MaterialApp(
      title: AppConstants.appTitle,
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        primaryColor: AppColors.tealAccent,
        scaffoldBackgroundColor: AppColors.darkBackground,
        cardColor: AppColors.cardBackground,
        colorScheme: const ColorScheme.dark().copyWith(
          secondary: AppColors.tealAccent,
          primary: AppColors.tealAccent,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        cardTheme: CardThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      home: const StartupScreen(),
    );
  }
}

class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  final _permissionService = PermissionService();

  @override
  void initState() {
    super.initState();
    _checkStartupConditions();
  }

  Future<void> _checkStartupConditions() async {
    try {
      print('StartupScreen: Checking startup conditions...');

      // Add a small delay to show the splash screen briefly
      await Future.delayed(const Duration(milliseconds: 1500));

      // Check for stored credentials
      final prefs = await SharedPreferences.getInstance();
      final storedToken = prefs.getString('token');
      final storedDeploymentCode = prefs.getString('deploymentCode');

      if (storedToken != null && storedDeploymentCode != null) {
        print(
            'StartupScreen: Found stored credentials, checking permissions...');

        // Check if critical permissions are still granted
        final hasPermissions =
            await _permissionService.hasAllCriticalPermissions();

        if (hasPermissions) {
          print('StartupScreen: Permissions valid, navigating to dashboard...');

          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => DashboardScreen(
                  token: storedToken,
                  deploymentCode: storedDeploymentCode,
                ),
              ),
            );
          }
          return;
        } else {
          print(
              'StartupScreen: Critical permissions missing, going to login...');

          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const LoginScreen()),
            );
          }
          return;
        }
      } else {
        print('StartupScreen: No stored credentials, checking permissions...');

        // No stored credentials, check if permissions are granted
        final hasPermissions =
            await _permissionService.hasAllCriticalPermissions();

        if (hasPermissions) {
          print('StartupScreen: Permissions granted, going to login...');

          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const LoginScreen()),
            );
          }
        } else {
          print(
              'StartupScreen: Permissions needed, going to permission screen...');

          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const PermissionScreen()),
            );
          }
        }
      }
    } catch (e) {
      print('StartupScreen: Error checking startup conditions: $e');

      // On error, default to permission screen
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const PermissionScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.darkBackground,
              AppColors.primaryRed.withOpacity(0.1),
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.primaryRed.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: AppColors.primaryRed.withOpacity(0.3)),
                ),
                child: Image.asset(
                  'assets/images/pnp_logo.png',
                  width: 120,
                  height: 120,
                  errorBuilder: (context, error, stackTrace) {
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
              ),

              const SizedBox(height: 32),

              // App title
              Text(
                AppConstants.appTitle.toUpperCase(),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryRed,
                  letterSpacing: 1.5,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 12),

              // App motto
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  AppConstants.appMotto,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.8,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              const SizedBox(height: 48),

              // Loading indicator
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.tealAccent),
              ),

              const SizedBox(height: 16),

              Text(
                'Initializing Security Module...',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[400],
                  fontWeight: FontWeight.w500,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                'Checking credentials and permissions',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
