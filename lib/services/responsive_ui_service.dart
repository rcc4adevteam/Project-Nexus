import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Comprehensive responsive UI service for auto-adjusting elements
class ResponsiveUIService {
  static final ResponsiveUIService _instance = ResponsiveUIService._internal();
  factory ResponsiveUIService() => _instance;
  ResponsiveUIService._internal();

  // Screen breakpoints
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 900;
  static const double desktopBreakpoint = 1200;

  // Base design dimensions (reference screen)
  static const double baseWidth = 375; // iPhone 11 Pro width
  static const double baseHeight = 812; // iPhone 11 Pro height

  /// Get current screen type based on width
  static ScreenType getScreenType(double width) {
    if (width < mobileBreakpoint) return ScreenType.mobile;
    if (width < tabletBreakpoint) return ScreenType.tablet;
    if (width < desktopBreakpoint) return ScreenType.desktop;
    return ScreenType.large;
  }

  /// Calculate responsive font size with auto-scaling
  static double getResponsiveFontSize({
    required BuildContext context,
    required double baseFontSize,
    double minSize = 10.0,
    double maxSize = 32.0,
    bool enableAutoScale = true,
  }) {
    final screenSize = MediaQuery.of(context).size;
    final orientation = MediaQuery.of(context).orientation;
    final textScaleFactor = MediaQuery.of(context).textScaleFactor;
    
    // Calculate scale factor based on screen width
    double scaleFactor = screenSize.width / baseWidth;
    
    // Adjust for orientation
    if (orientation == Orientation.landscape) {
      scaleFactor *= 0.9; // Slightly smaller in landscape
    }
    
    // Apply base scaling
    double calculatedSize = baseFontSize * scaleFactor;
    
    // Apply text scale factor if auto-scale is enabled
    if (enableAutoScale) {
      calculatedSize *= math.min(textScaleFactor, 1.3); // Cap at 130%
    }
    
    // Clamp to min/max bounds
    return calculatedSize.clamp(minSize, maxSize);
  }

  /// Get responsive padding based on screen size
  static EdgeInsets getResponsivePadding({
    required BuildContext context,
    double basePadding = 16.0,
    double minPadding = 8.0,
    double maxPadding = 32.0,
  }) {
    final screenSize = MediaQuery.of(context).size;
    final scaleFactor = screenSize.width / baseWidth;
    final calculatedPadding = (basePadding * scaleFactor).clamp(minPadding, maxPadding);
    
    return EdgeInsets.all(calculatedPadding);
  }

  /// Get responsive margin
  static EdgeInsets getResponsiveMargin({
    required BuildContext context,
    double baseMargin = 8.0,
    double minMargin = 4.0,
    double maxMargin = 16.0,
  }) {
    final screenSize = MediaQuery.of(context).size;
    final scaleFactor = screenSize.width / baseWidth;
    final calculatedMargin = (baseMargin * scaleFactor).clamp(minMargin, maxMargin);
    
    return EdgeInsets.all(calculatedMargin);
  }

  /// Get responsive icon size
  static double getResponsiveIconSize({
    required BuildContext context,
    double baseIconSize = 24.0,
    double minSize = 16.0,
    double maxSize = 48.0,
  }) {
    final screenSize = MediaQuery.of(context).size;
    final scaleFactor = screenSize.width / baseWidth;
    final calculatedSize = (baseIconSize * scaleFactor).clamp(minSize, maxSize);
    
    return calculatedSize;
  }

  /// Get responsive button height
  static double getResponsiveButtonHeight({
    required BuildContext context,
    double baseHeight = 48.0,
    double minHeight = 36.0,
    double maxHeight = 64.0,
  }) {
    final screenSize = MediaQuery.of(context).size;
    final scaleFactor = screenSize.width / baseWidth;
    final calculatedHeight = (baseHeight * scaleFactor).clamp(minHeight, maxHeight);
    
    return calculatedHeight;
  }

  /// Calculate grid cross axis count based on screen size
  static int getGridCrossAxisCount(BuildContext context, {
    int baseMobileCount = 2,
    int baseTabletCount = 3,
    int baseDesktopCount = 4,
  }) {
    final screenType = getScreenType(MediaQuery.of(context).size.width);
    final orientation = MediaQuery.of(context).orientation;
    
    int count;
    switch (screenType) {
      case ScreenType.mobile:
        count = baseMobileCount;
        break;
      case ScreenType.tablet:
        count = baseTabletCount;
        break;
      case ScreenType.desktop:
        count = baseDesktopCount;
        break;
      case ScreenType.large:
        count = baseDesktopCount + 1;
        break;
    }
    
    // Adjust for landscape orientation
    if (orientation == Orientation.landscape && screenType == ScreenType.mobile) {
      count += 1;
    }
    
    return count;
  }
}

enum ScreenType { mobile, tablet, desktop, large }

/// Extension to add responsive utilities to BuildContext
extension ResponsiveContext on BuildContext {
  /// Check if current screen is mobile
  bool get isMobile => MediaQuery.of(this).size.width < ResponsiveUIService.mobileBreakpoint;
  
  /// Check if current screen is tablet
  bool get isTablet => MediaQuery.of(this).size.width >= ResponsiveUIService.mobileBreakpoint &&
                       MediaQuery.of(this).size.width < ResponsiveUIService.tabletBreakpoint;
  
  /// Check if current screen is desktop
  bool get isDesktop => MediaQuery.of(this).size.width >= ResponsiveUIService.tabletBreakpoint;
  
  /// Check if current orientation is landscape
  bool get isLandscape => MediaQuery.of(this).orientation == Orientation.landscape;
  
  /// Check if current screen is small (height < 700)
  bool get isSmallScreen => MediaQuery.of(this).size.height < 700;
  
  /// Get responsive font size
  double responsiveFont(double baseSize, {double? minSize, double? maxSize}) {
    return ResponsiveUIService.getResponsiveFontSize(
      context: this,
      baseFontSize: baseSize,
      minSize: minSize ?? baseSize * 0.7,
      maxSize: maxSize ?? baseSize * 1.5,
    );
  }
  
  /// Get responsive padding
  EdgeInsets responsivePadding([double basePadding = 16.0]) {
    return ResponsiveUIService.getResponsivePadding(
      context: this,
      basePadding: basePadding,
    );
  }
  
  /// Get responsive margin
  EdgeInsets responsiveMargin([double baseMargin = 8.0]) {
    return ResponsiveUIService.getResponsiveMargin(
      context: this,
      baseMargin: baseMargin,
    );
  }
}

/// Mixin for responsive state management
mixin ResponsiveStateMixin<T extends StatefulWidget> on State<T> {
  late MediaQueryData _mediaQuery;
  late double _scaleFactor;
  late ScreenType _screenType;
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateResponsiveData();
  }
  
  void _updateResponsiveData() {
    _mediaQuery = MediaQuery.of(context);
    _scaleFactor = _mediaQuery.size.width / ResponsiveUIService.baseWidth;
    _screenType = ResponsiveUIService.getScreenType(_mediaQuery.size.width);
  }
  
  /// Get scaled value based on screen size
  double scale(double value) => value * _scaleFactor;
  
  /// Get clamped scaled value
  double scaleClamp(double value, double min, double max) {
    return (value * _scaleFactor).clamp(min, max);
  }
  
  /// Check if screen type matches
  bool isScreenType(ScreenType type) => _screenType == type;
  
  /// Get responsive font size
  double getResponsiveFont(double baseSize) {
    return ResponsiveUIService.getResponsiveFontSize(
      context: context,
      baseFontSize: baseSize,
    );
  }
}