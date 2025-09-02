import 'package:flutter/material.dart';

class ErrorHandlingService {
  static final ErrorHandlingService _instance = ErrorHandlingService._internal();
  factory ErrorHandlingService() => _instance;
  ErrorHandlingService._internal();

  // Convert technical errors to user-friendly messages
  static String getUserFriendlyError(dynamic error) {
    if (error == null) {
      return 'An unexpected error occurred. Please try again.';
    }

    final errorString = error.toString().toLowerCase();

    // Network and connectivity errors
    if (errorString.contains('network') || errorString.contains('connection')) {
      return 'Unable to connect to the server. Please check your internet connection and try again.';
    }
    
    if (errorString.contains('timeout')) {
      return 'The request took too long to complete. Please check your connection and try again.';
    }
    
    if (errorString.contains('socket')) {
      return 'Connection lost. Please check your internet connection and try again.';
    }

    // Authentication errors
    if (errorString.contains('unauthorized') || errorString.contains('401')) {
      return 'Your session has expired. Please log in again.';
    }
    
    if (errorString.contains('forbidden') || errorString.contains('403')) {
      return 'You don\'t have permission to perform this action.';
    }
    
    if (errorString.contains('token') || errorString.contains('authentication')) {
      return 'Authentication failed. Please log in again.';
    }

    // Server errors
    if (errorString.contains('500') || errorString.contains('internal server error')) {
      return 'The server encountered an error. Please try again later.';
    }
    
    if (errorString.contains('502') || errorString.contains('bad gateway')) {
      return 'The server is temporarily unavailable. Please try again later.';
    }
    
    if (errorString.contains('503') || errorString.contains('service unavailable')) {
      return 'The service is temporarily unavailable. Please try again later.';
    }
    
    if (errorString.contains('504') || errorString.contains('gateway timeout')) {
      return 'The server is taking too long to respond. Please try again later.';
    }

    // Client errors
    if (errorString.contains('400') || errorString.contains('bad request')) {
      return 'The request was invalid. Please check your input and try again.';
    }
    
    if (errorString.contains('404') || errorString.contains('not found')) {
      return 'The requested resource was not found.';
    }
    
    if (errorString.contains('409') || errorString.contains('conflict')) {
      return 'There was a conflict with the current state. Please try again.';
    }
    
    if (errorString.contains('422') || errorString.contains('unprocessable entity')) {
      return 'The request could not be processed. Please check your input and try again.';
    }

    // Location and permission errors
    if (errorString.contains('location') || errorString.contains('gps')) {
      if (errorString.contains('permission')) {
        return 'Location permission is required. Please enable location access in your device settings.';
      }
      if (errorString.contains('disabled')) {
        return 'Location services are disabled. Please enable GPS in your device settings.';
      }
      if (errorString.contains('unavailable')) {
        return 'Location is currently unavailable. Please try again in a few moments.';
      }
      return 'Unable to get your location. Please check your GPS settings and try again.';
    }
    
    if (errorString.contains('permission')) {
      return 'Permission is required to perform this action. Please grant the necessary permissions.';
    }

    // Battery and device errors
    if (errorString.contains('battery')) {
      if (errorString.contains('low')) {
        return 'Battery is too low to perform this operation. Please charge your device.';
      }
      return 'Unable to access battery information. Please check your device settings.';
    }
    
    if (errorString.contains('camera')) {
      return 'Camera permission is required. Please enable camera access in your device settings.';
    }
    
    if (errorString.contains('microphone')) {
      return 'Microphone permission is required. Please enable microphone access in your device settings.';
    }
    
    if (errorString.contains('storage')) {
      return 'Storage permission is required. Please enable storage access in your device settings.';
    }

    // File and data errors
    if (errorString.contains('file') || errorString.contains('document')) {
      if (errorString.contains('not found')) {
        return 'The file was not found. It may have been moved or deleted.';
      }
      if (errorString.contains('corrupted')) {
        return 'The file appears to be corrupted and cannot be opened.';
      }
      if (errorString.contains('access denied')) {
        return 'Access to the file was denied. Please check your permissions.';
      }
      return 'Unable to access the file. Please try again.';
    }
    
    if (errorString.contains('database') || errorString.contains('sql')) {
      return 'Unable to access the database. Please try again later.';
    }
    
    if (errorString.contains('json') || errorString.contains('parse')) {
      return 'The data format is invalid. Please try again later.';
    }

    // QR code and scanning errors
    if (errorString.contains('qr') || errorString.contains('barcode')) {
      if (errorString.contains('invalid')) {
        return 'The QR code is invalid or has expired. Please scan a valid code.';
      }
      if (errorString.contains('camera')) {
        return 'Unable to access camera for QR code scanning. Please check your camera permissions.';
      }
      return 'Unable to scan the QR code. Please try again.';
    }

    // Session and state errors
    if (errorString.contains('session')) {
      if (errorString.contains('expired')) {
        return 'Your session has expired. Please log in again.';
      }
      if (errorString.contains('invalid')) {
        return 'Your session is invalid. Please log in again.';
      }
      return 'Session error occurred. Please try logging in again.';
    }
    
    if (errorString.contains('state')) {
      return 'The application state is invalid. Please restart the app and try again.';
    }

    // Memory and performance errors
    if (errorString.contains('memory') || errorString.contains('out of memory')) {
      return 'The device is running low on memory. Please close other apps and try again.';
    }
    
    if (errorString.contains('timeout') || errorString.contains('slow')) {
      return 'The operation is taking longer than expected. Please wait or try again.';
    }

    // Generic error patterns
    if (errorString.contains('exception')) {
      return 'An unexpected error occurred. Please try again.';
    }
    
    if (errorString.contains('error')) {
      return 'An error occurred. Please try again.';
    }
    
    if (errorString.contains('failed')) {
      return 'The operation failed. Please try again.';
    }
    
    if (errorString.contains('unable')) {
      return 'Unable to complete the operation. Please try again.';
    }
    
    if (errorString.contains('cannot')) {
      return 'Cannot complete the operation. Please try again.';
    }

    // Default fallback
    return 'Something went wrong. Please try again.';
  }

  // Get error icon based on error type
  static IconData getErrorIcon(dynamic error) {
    if (error == null) return Icons.error_outline;

    final errorString = error.toString().toLowerCase();

    if (errorString.contains('network') || errorString.contains('connection')) {
      return Icons.wifi_off;
    }
    
    if (errorString.contains('location') || errorString.contains('gps')) {
      return Icons.location_off;
    }
    
    if (errorString.contains('permission')) {
      return Icons.block;
    }
    
    if (errorString.contains('battery')) {
      return Icons.battery_alert;
    }
    
    if (errorString.contains('camera')) {
      return Icons.camera_alt_outlined;
    }
    
    if (errorString.contains('file')) {
      return Icons.file_copy;
    }
    
    if (errorString.contains('qr')) {
      return Icons.qr_code_scanner;
    }
    
    if (errorString.contains('session') || errorString.contains('authentication')) {
      return Icons.lock_outline;
    }
    
    if (errorString.contains('timeout')) {
      return Icons.timer_off;
    }
    
    if (errorString.contains('server')) {
      return Icons.dns;
    }

    return Icons.error_outline;
  }

  // Get error color based on error severity
  static Color getErrorColor(dynamic error) {
    if (error == null) return Colors.orange;

    final errorString = error.toString().toLowerCase();

    // Critical errors (red)
    if (errorString.contains('unauthorized') || 
        errorString.contains('forbidden') || 
        errorString.contains('500') ||
        errorString.contains('corrupted')) {
      return Colors.red;
    }
    
    // Warning errors (orange)
    if (errorString.contains('timeout') || 
        errorString.contains('unavailable') || 
        errorString.contains('low')) {
      return Colors.orange;
    }
    
    // Info errors (blue)
    if (errorString.contains('not found') || 
        errorString.contains('invalid') || 
        errorString.contains('expired')) {
      return Colors.blue;
    }

    return Colors.orange;
  }

  // Get retry suggestion based on error type
  static String getRetrySuggestion(dynamic error) {
    if (error == null) return 'Please try again.';

    final errorString = error.toString().toLowerCase();

    if (errorString.contains('network') || errorString.contains('connection')) {
      return 'Check your internet connection and try again.';
    }
    
    if (errorString.contains('timeout')) {
      return 'Wait a moment and try again.';
    }
    
    if (errorString.contains('location')) {
      return 'Enable GPS and try again.';
    }
    
    if (errorString.contains('permission')) {
      return 'Grant the required permissions and try again.';
    }
    
    if (errorString.contains('session')) {
      return 'Log in again and try the operation.';
    }
    
    if (errorString.contains('server')) {
      return 'Try again in a few minutes.';
    }

    return 'Please try again.';
  }

  // Check if error is retryable
  static bool isRetryable(dynamic error) {
    if (error == null) return true;

    final errorString = error.toString().toLowerCase();

    // Non-retryable errors
    if (errorString.contains('unauthorized') || 
        errorString.contains('forbidden') || 
        errorString.contains('not found') ||
        errorString.contains('invalid') ||
        errorString.contains('corrupted')) {
      return false;
    }

    // Retryable errors
    if (errorString.contains('network') || 
        errorString.contains('connection') || 
        errorString.contains('timeout') ||
        errorString.contains('unavailable') ||
        errorString.contains('server')) {
      return true;
    }

    return true;
  }

  // Get error category for analytics
  static String getErrorCategory(dynamic error) {
    if (error == null) return 'unknown';

    final errorString = error.toString().toLowerCase();

    if (errorString.contains('network') || errorString.contains('connection')) {
      return 'network';
    }
    
    if (errorString.contains('location') || errorString.contains('gps')) {
      return 'location';
    }
    
    if (errorString.contains('permission')) {
      return 'permission';
    }
    
    if (errorString.contains('authentication') || errorString.contains('session')) {
      return 'authentication';
    }
    
    if (errorString.contains('server')) {
      return 'server';
    }
    
    if (errorString.contains('file') || errorString.contains('data')) {
      return 'data';
    }
    
    if (errorString.contains('device') || errorString.contains('battery')) {
      return 'device';
    }

    return 'general';
  }
}
