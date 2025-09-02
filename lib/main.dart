import 'package:flutter/material.dart';
import 'package:project_nexus/screens/splash_screen.dart';
import 'package:provider/provider.dart';
import 'package:project_nexus/services/background_service.dart';
import 'package:project_nexus/services/permission_service.dart';
import 'package:project_nexus/services/theme_provider.dart';
import 'package:project_nexus/services/authentication_service.dart';
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
    // within the function itself and will not crash the app.
    _initializeBackgroundServiceAsync();

    print('Main: Starting app...');
    runApp(
      ChangeNotifierProvider(
        create: (_) => ThemeProvider(),
        child: const MyApp(),
      ),
    );
  } catch (e, stackTrace) {
    print('Main: Error in main: $e');
    print('Main: Stack trace: $stackTrace');
    // Still try to run the app
    runApp(
      ChangeNotifierProvider(
        create: (_) => ThemeProvider(),
        child: const MyApp(),
      ),
    );
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
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          title: AppConstants.appTitle,
          debugShowCheckedModeBanner: false,
          theme: AppThemes.lightTheme,
          darkTheme: AppThemes.darkTheme,
          themeMode: themeProvider.themeMode,
          home: const SplashScreen(),
        );
      },
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
  final _authService = AuthenticationService();
  bool _isInitializing = true;
  String _statusMessage = 'Initializing...';

  @override
  void initState() {
    super.initState();
    _initializeAndCheckAuth();
  }

  Future<void> _initializeAndCheckAuth() async {
    try {
      print('StartupScreen: Starting offline-first authentication...');

      // Add a small delay to show the splash screen briefly
      await Future.delayed(const Duration(milliseconds: 1500));

      setState(() {
        _statusMessage = 'Checking network connectivity...';
      });

      // Initialize authentication service
      await _authService.initialize();

      setState(() {
        _statusMessage = 'Validating session...';
      });

      // Check authentication status using offline-first logic
      final authStatus = await _authService.checkAuthenticationStatus();

      print('StartupScreen: Authentication status: $authStatus');

      // Check permissions regardless of auth status
      final hasPermissions =
          await _permissionService.hasAllCriticalPermissions();

      if (mounted) {
        switch (authStatus) {
          case AuthStatus.authenticated:
          case AuthStatus.authenticatedOffline:
            if (hasPermissions) {
              print(
                  'StartupScreen: User authenticated and permissions granted, navigating to dashboard...');

              // Get current credentials from auth service
              final token = _authService.currentToken;
              final deploymentCode = _authService.currentDeploymentCode;

              if (token != null && deploymentCode != null) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => DashboardScreen(
                      token: token,
                      deploymentCode: deploymentCode,
                    ),
                  ),
                );
                return;
              }
            } else {
              print(
                  'StartupScreen: Critical permissions missing, going to permission screen...');
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (context) => const PermissionScreen()),
              );
              return;
            }
            break;

          case AuthStatus.noCredentials:
          case AuthStatus.invalidCredentials:
            if (hasPermissions) {
              print('StartupScreen: No valid credentials, going to login...');
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
              );
            } else {
              print(
                  'StartupScreen: No credentials and permissions needed, going to permission screen...');
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (context) => const PermissionScreen()),
              );
            }
            break;

          case AuthStatus.error:
            print(
                'StartupScreen: Authentication error, defaulting to permission screen...');
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const PermissionScreen()),
            );
            break;
        }
      }
    } catch (e) {
      print('StartupScreen: Error during authentication: $e');

      // On error, default to permission screen
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const PermissionScreen()),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _authService.dispose();
    super.dispose();
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
    final logoSize = isTablet ? 160.0 : (isSmallScreen ? 80.0 : 120.0);
    final titleFontSize = isTablet ? 32.0 : (isSmallScreen ? 18.0 : 24.0);
    final mottoFontSize = isTablet ? 18.0 : (isSmallScreen ? 12.0 : 14.0);
    final statusFontSize = isTablet ? 20.0 : (isSmallScreen ? 14.0 : 16.0);
    final horizontalPadding = isTablet ? 40.0 : (isSmallScreen ? 20.0 : 30.0);
    final verticalPadding = isTablet ? 12.0 : (isSmallScreen ? 6.0 : 8.0);
    final spacingLarge = isTablet ? 64.0 : (isSmallScreen ? 32.0 : 48.0);
    final spacingMedium = isTablet ? 48.0 : (isSmallScreen ? 24.0 : 32.0);
    final spacingSmall = isTablet ? 24.0 : (isSmallScreen ? 12.0 : 16.0);
    final borderRadius = isTablet ? 32.0 : (isSmallScreen ? 16.0 : 20.0);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo with responsive sizing
                Image.asset(
                  'assets/images/pnp_logo.png',
                  width: logoSize,
                  height: logoSize,
                  fit: BoxFit.contain,
                ),
                SizedBox(height: spacingMedium),

                // Title with responsive font size
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    AppConstants.appTitle.toUpperCase(),
                    style: TextStyle(
                      fontSize: titleFontSize,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                SizedBox(height: spacingSmall),

                // Motto container with responsive sizing
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding * 0.5,
                    vertical: verticalPadding,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(borderRadius),
                  ),
                  child: Text(
                    AppConstants.appMotto,
                    style: TextStyle(
                      fontSize: mottoFontSize,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.8,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                SizedBox(height: spacingLarge),

                // Progress indicator with responsive sizing
                SizedBox(
                  width: isTablet ? 48.0 : (isSmallScreen ? 32.0 : 40.0),
                  height: isTablet ? 48.0 : (isSmallScreen ? 32.0 : 40.0),
                  child: CircularProgressIndicator(
                    strokeWidth: isTablet ? 4.0 : (isSmallScreen ? 2.0 : 3.0),
                    valueColor: AlwaysStoppedAnimation<Color>(
                        Theme.of(context).colorScheme.primary),
                  ),
                ),
                SizedBox(height: spacingSmall),

                // Status text with responsive font size
                Text(
                  _statusMessage,
                  style: TextStyle(
                    fontSize: statusFontSize,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
