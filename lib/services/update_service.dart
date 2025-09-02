import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:app_settings/app_settings.dart';
import 'package:flutter/services.dart';

class UpdateInfo {
  final String latestVersion;
  final String downloadUrl;
  final String changelog;
  final bool isRequired;
  final String releaseDate;
  final String fileSize;
  final String minAndroidVersion;
  final String buildNumber;

  UpdateInfo({
    required this.latestVersion,
    required this.downloadUrl,
    required this.changelog,
    required this.isRequired,
    required this.releaseDate,
    required this.fileSize,
    required this.minAndroidVersion,
    required this.buildNumber,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      latestVersion: json['latestVersion'] ?? '',
      downloadUrl: json['downloadUrl'] ?? '',
      changelog: json['changelog'] ?? '',
      isRequired: json['isRequired'] ?? false,
      releaseDate: json['releaseDate'] ?? '',
      fileSize: json['fileSize'] ?? '',
      minAndroidVersion: json['minAndroidVersion'] ?? '21',
      buildNumber: json['buildNumber'] ?? '',
    );
  }

  factory UpdateInfo.fromGithubRelease(Map<String, dynamic> json) {
    final assets = json['assets'] as List<dynamic>?;
    final apkAsset = assets?.firstWhere(
      (asset) => asset['name'].toString().endsWith('.apk'),
      orElse: () => null,
    );

    return UpdateInfo(
      latestVersion: json['tag_name'] ?? '',
      downloadUrl: apkAsset != null ? apkAsset['browser_download_url'] : '',
      changelog: json['body'] ?? 'No changelog provided.',
      isRequired: json['prerelease'] ?? false,
      releaseDate: json['published_at'] ?? '',
      fileSize: apkAsset != null ? '${(apkAsset['size'] / 1024 / 1024).toStringAsFixed(2)} MB' : 'N/A',
      minAndroidVersion: '21', // Assuming a default, adjust if needed
      buildNumber: '', // Not directly available in this format
    );
  }
}

class UpdateCheckResult {
  final bool hasUpdate;
  final UpdateInfo? updateInfo;
  final String? message;
  final String? error;
  final String currentVersion;
  final String latestVersion;

  UpdateCheckResult({
    required this.hasUpdate,
    this.updateInfo,
    this.message,
    this.error,
    required this.currentVersion,
    required this.latestVersion,
  });

  factory UpdateCheckResult.fromJson(Map<String, dynamic> json, {String currentVersion = ''}) {
    final latestVersion = json['tag_name'] ?? '';
    final hasUpdate = latestVersion.isNotEmpty && latestVersion != currentVersion;

    return UpdateCheckResult(
      hasUpdate: hasUpdate,
      updateInfo: hasUpdate ? UpdateInfo.fromGithubRelease(json) : null,
      message: hasUpdate ? 'An update is available.' : 'No new updates available.',
      currentVersion: currentVersion,
      latestVersion: latestVersion,
    );
  }
}

class UpdateService {
  static const String _updateCheckUrl = 'https://api.github.com/repos/rcc4adevteam/project-nexus/releases/latest';

  Future<UpdateCheckResult> checkForUpdates() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final response = await http.get(
        Uri.parse(_updateCheckUrl),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        return UpdateCheckResult.fromJson(jsonResponse, currentVersion: currentVersion);
      } else {
        return UpdateCheckResult(
          hasUpdate: false,
          currentVersion: currentVersion,
          latestVersion: currentVersion,
          error: 'HTTP ${response.statusCode}: ${response.reasonPhrase}',
        );
      }
    } catch (e) {
      final currentVersion = await _getCurrentVersion();
      return UpdateCheckResult(
        hasUpdate: false,
        currentVersion: currentVersion,
        latestVersion: currentVersion,
        error: 'Network error: $e',
      );
    }
  }

  // ... (the rest of the class remains the same)
  // Download APK file with path tracking
  Future<DownloadResult> downloadApkWithPath(String downloadUrl, Function(double) onProgress) async {
    try {
      // Get download directory - use app-specific directory for Android 11+
      final directory = await getDownloadDirectory();
      if (directory == null) {
        return DownloadResult(
          success: false,
          error: 'Could not access download directory',
        );
      }

      final fileName = 'nexus_update_${DateTime.now().millisecondsSinceEpoch}.apk';
      final file = File('${directory.path}/$fileName');

      // Download file with progress
      final request = http.Request('GET', Uri.parse(downloadUrl));
      final streamedResponse = await http.Client().send(request);
      
      final totalBytes = streamedResponse.contentLength ?? 0;
      int downloadedBytes = 0;

      final sink = file.openWrite();
      await for (final chunk in streamedResponse.stream) {
        sink.add(chunk);
        downloadedBytes += chunk.length;
        
        if (totalBytes > 0) {
          final progress = downloadedBytes / totalBytes;
          onProgress(progress);
        }
      }
      
      await sink.close();
      
      // Verify file exists and has content
      if (await file.exists() && await file.length() > 0) {
        return DownloadResult(
          success: true,
          filePath: file.path,
        );
      } else {
        return DownloadResult(
          success: false,
          error: 'Downloaded file is invalid or empty',
        );
      }
    } catch (e) {
      return DownloadResult(
        success: false,
        error: 'Download failed: $e',
      );
    }
  }

  // Install APK using proper FileProvider for Android 7+
  Future<bool> installApk(String apkPath) async {
    try {
      // Check if file exists
      final apkFile = File(apkPath);
      if (!await apkFile.exists()) {
        throw Exception('APK file not found: $apkPath');
      }

      // Request install permission
      final status = await Permission.requestInstallPackages.request();
      if (!status.isGranted) {
        throw Exception('Install permission not granted');
      }

      if (Platform.isAndroid) {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        final sdkInt = androidInfo.version.sdkInt;
        
        if (sdkInt >= 24) { // Android 7+ (API 24+)
          // Use FileProvider for Android 7+
          return await _installApkWithFileProvider(apkPath);
        } else {
          // Use basic intent for older Android versions
          return await _installApkWithIntent(apkPath);
        }
      } else {
        throw Exception('APK installation is only supported on Android');
      }
    } catch (e) {
      throw Exception('Installation failed: $e');
    }
  }

  // Install APK using FileProvider (Android 7+)
  Future<bool> _installApkWithFileProvider(String apkPath) async {
    try {
      // Use platform channel to trigger installation with FileProvider
      const platform = MethodChannel('com.projectnexus.app/installer');
      final result = await platform.invokeMethod('installApk', {
        'apkPath': apkPath,
        'authority': 'com.example.project_nexus.fileprovider',
      });
      
      return result == true;
    } catch (e) {
      print('Platform channel installation failed: $e');
      // Fallback to intent method if platform channel fails
      return await _installApkWithIntent(apkPath);
    }
  }

  // Install APK using basic intent (older Android versions)
  Future<bool> _installApkWithIntent(String apkPath) async {
    try {
      // Fallback to Process.run
      final result = await Process.run('am', [
        'start',
        '-a',
        'android.intent.action.VIEW',
        '-d',
        'file://$apkPath',
        '-t',
        'application/vnd.android.package-archive'
      ]);

      return result.exitCode == 0;
    } catch (e) {
      print('Intent installation failed: $e');
      throw Exception('Intent installation failed: $e');
    }
  }

  // Get current app version
  Future<String> _getCurrentVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return packageInfo.version;
    } catch (e) {
      return 'Unknown';
    }
  }

  // Get platform info
  Future<String> _getPlatform() async {
    if (Platform.isAndroid) {
      return 'android';
    } else if (Platform.isIOS) {
      return 'ios';
    } else {
      return 'unknown';
    }
  }

  // Get download directory
  Future<Directory?> getDownloadDirectory() async {
    try {
      if (Platform.isAndroid) {
        // For Android, use the app's external files directory
        // This doesn't require special permissions on Android 11+
        final appDir = await getExternalStorageDirectory();
        if (appDir != null) {
          // Create a downloads subdirectory
          final downloadDir = Directory('${appDir.path}/downloads');
          if (!await downloadDir.exists()) {
            await downloadDir.create(recursive: true);
          }
          print('UpdateService: Download directory: ${downloadDir.path}');
          return downloadDir;
        } else {
          print('UpdateService: Could not get external storage directory');
        }
      } else if (Platform.isIOS) {
        // For iOS, use the documents directory
        return await getApplicationDocumentsDirectory();
      }
      return null;
    } catch (e) {
      print('UpdateService: Error getting download directory: $e');
      return null;
    }
  }

  // Check if device meets minimum requirements
  Future<bool> checkDeviceCompatibility(String minAndroidVersion) async {
    if (!Platform.isAndroid) return true;
    
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final sdkInt = androidInfo.version.sdkInt;
      
      return sdkInt >= int.parse(minAndroidVersion);
    } catch (e) {
      return false;
    }
  }

  // Check required permissions
  Future<bool> checkRequiredPermissions() async {
    if (!Platform.isAndroid) return true;
    
    try {
      // Check install permission - this is a special permission that requires user action
      final installStatus = await Permission.requestInstallPackages.status;
      if (!installStatus.isGranted) {
        // Try to request the permission
        final requestResult = await Permission.requestInstallPackages.request();
        if (!requestResult.isGranted) {
          return false;
        }
      }
      
      // For older Android versions, check storage permission
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final sdkInt = androidInfo.version.sdkInt;
      
      if (sdkInt < 30) { // Android 10 and below
        final storageStatus = await Permission.storage.status;
        if (!storageStatus.isGranted) {
          final requestResult = await Permission.storage.request();
          if (!requestResult.isGranted) {
            return false;
          }
        }
      }
      
      return true;
    } catch (e) {
      print('UpdateService: Permission check error: $e');
      return false;
    }
  }

  // Request all required permissions
  Future<bool> requestAllPermissions() async {
    if (!Platform.isAndroid) return true;
    
    try {
      // Request install permission first
      final installResult = await Permission.requestInstallPackages.request();
      if (!installResult.isGranted) {
        return false;
      }
      
      // For older Android versions, request storage permission
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final sdkInt = androidInfo.version.sdkInt;
      
      if (sdkInt < 30) { // Android 10 and below
        final storageResult = await Permission.storage.request();
        if (!storageResult.isGranted) {
          return false;
        }
      }
      
      return true;
    } catch (e) {
      print('UpdateService: Permission request error: $e');
      return false;
    }
  }

  // Open app settings
  Future<void> openAppSettings() async {
    try {
      await AppSettings.openAppSettings();
    } catch (e) {
      print('UpdateService: Error opening app settings: $e');
    }
  }

  // Format file size
  String formatFileSize(String fileSize) {
    return fileSize;
  }

  // Format release date
  String formatReleaseDate(String releaseDate) {
    try {
      final date = DateTime.parse(releaseDate);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return releaseDate;
    }
  }
}

class DownloadResult {
  final bool success;
  final String? filePath;
  final String? error;

  DownloadResult({
    required this.success,
    this.filePath,
    this.error,
  });
}