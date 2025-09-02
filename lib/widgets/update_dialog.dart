import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/update_service.dart';

class UpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;
  final String currentVersion;

  const UpdateDialog({
    super.key,
    required this.updateInfo,
    required this.currentVersion,
  });

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isDownloading = false;
  bool _isInstalling = false;
  bool _autoInstall = true; // New: Control auto-install behavior
  double _downloadProgress = 0.0;
  String? _downloadError;
  String? _apkPath;

  @override
  void initState() {
    super.initState();
    _loadAutoInstallPreference();
  }

  // Load auto-install preference from shared preferences
  Future<void> _loadAutoInstallPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _autoInstall = prefs.getBool('auto_install_updates') ?? true;
      });
    } catch (e) {
      // Keep default value if loading fails
      print('Error loading auto-install preference: $e');
    }
  }

  // Save auto-install preference to shared preferences
  Future<void> _saveAutoInstallPreference(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('auto_install_updates', value);
    } catch (e) {
      print('Error saving auto-install preference: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.system_update,
            color: Theme.of(context).colorScheme.primary,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Update Available (v${widget.updateInfo.latestVersion})',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Current vs Latest version
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Current: v${widget.currentVersion} → Latest: v${widget.updateInfo.latestVersion}',
                      style: TextStyle(
                        color: Colors.blue[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Changelog
            const Text(
              'What\'s New:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.withOpacity(0.3)),
              ),
              child: Text(
                widget.updateInfo.changelog,
                style: const TextStyle(fontSize: 14),
              ),
            ),
            const SizedBox(height: 16),

            // Update details
            _buildDetailRow('File Size:', widget.updateInfo.fileSize),
            _buildDetailRow('Release Date:', _formatDate(widget.updateInfo.releaseDate)),
            if (widget.updateInfo.isRequired)
              _buildDetailRow('Required:', 'Yes', isRequired: true),

            // Auto-install option
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome, color: Colors.orange[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Checkbox(
                              value: _autoInstall,
                              onChanged: (value) async {
                                final newValue = value ?? true;
                                setState(() {
                                  _autoInstall = newValue;
                                });
                                await _saveAutoInstallPreference(newValue);
                              },
                              activeColor: Colors.orange[700],
                            ),
                            Expanded(
                              child: Text(
                                'Auto-install after download',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange[700],
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'When enabled, the app will automatically start installation after successful download.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Download progress
            if (_isDownloading) ...[
              const SizedBox(height: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Downloading...'),
                      Text('${(_downloadProgress * 100).toInt()}%'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _downloadProgress,
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ],

            // Installation progress
            if (_isInstalling) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[700]!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Installing Update...',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[700],
                            ),
                          ),
                          Text(
                            'Please wait while the update is being installed.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

                         // Error message
             if (_downloadError != null) ...[
               const SizedBox(height: 16),
               Container(
                 padding: const EdgeInsets.all(12),
                 decoration: BoxDecoration(
                   color: Colors.red.withOpacity(0.1),
                   borderRadius: BorderRadius.circular(8),
                   border: Border.all(color: Colors.red.withOpacity(0.3)),
                 ),
                 child: Column(
                   crossAxisAlignment: CrossAxisAlignment.start,
                   children: [
                     Row(
                       children: [
                         Icon(Icons.error, color: Colors.red[700], size: 20),
                         SizedBox(width: 8),
                         Expanded(
                           child: Text(
                             'Permission Required',
                             style: TextStyle(
                               color: Colors.red[700],
                               fontSize: 16,
                               fontWeight: FontWeight.bold,
                             ),
                           ),
                         ),
                       ],
                     ),
                     SizedBox(height: 8),
                     Text(
                       _downloadError!,
                       style: TextStyle(
                         color: Colors.red[700],
                         fontSize: 14,
                       ),
                     ),
                     SizedBox(height: 12),
                     Text(
                       'Choose an option to resolve the issue:',
                       style: TextStyle(
                         color: Colors.red[700],
                         fontSize: 12,
                         fontStyle: FontStyle.italic,
                       ),
                     ),
                     SizedBox(height: 8),
                     Row(
                       children: [
                         Expanded(
                           child: ElevatedButton.icon(
                             onPressed: _requestPermissions,
                             icon: Icon(Icons.security, size: 18),
                             label: Text('Grant Permissions'),
                             style: ElevatedButton.styleFrom(
                               backgroundColor: Colors.red[700],
                               foregroundColor: Colors.white,
                               padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                             ),
                           ),
                         ),
                         SizedBox(width: 8),
                         Expanded(
                           child: ElevatedButton.icon(
                             onPressed: _openAppSettings,
                             icon: Icon(Icons.settings, size: 18),
                             label: Text('Open Settings'),
                             style: ElevatedButton.styleFrom(
                               backgroundColor: Colors.blue[700],
                               foregroundColor: Colors.white,
                               padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                             ),
                           ),
                         ),
                       ],
                     ),
                     SizedBox(height: 8),
                     if (_apkPath != null && _apkPath != 'Downloaded successfully')
                       SizedBox(
                         width: double.infinity,
                         child: ElevatedButton.icon(
                           onPressed: _openFileManager,
                           icon: Icon(Icons.folder_open, size: 18),
                           label: Text('Manual Installation Guide'),
                           style: ElevatedButton.styleFrom(
                             backgroundColor: Colors.green[700],
                             foregroundColor: Colors.white,
                             padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                           ),
                         ),
                       ),
                   ],
                 ),
               ),
             ],
          ],
        ),
      ),
      actions: [
        if (!_isDownloading && !_isInstalling) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Later'),
          ),
          ElevatedButton.icon(
            onPressed: _startUpdate,
            icon: const Icon(Icons.download),
            label: const Text('Update Now'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ] else if (_isDownloading) ...[
          if (_apkPath != null)
            ElevatedButton.icon(
              onPressed: _installUpdate,
              icon: const Icon(Icons.install_mobile),
              label: const Text('Install'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          TextButton(
            onPressed: _isDownloading ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ] else if (_isInstalling) ...[
          // Show only cancel button during installation
          TextButton(
            onPressed: null, // Disable during installation
            child: const Text('Installing...'),
          ),
        ],
      ],
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isRequired = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: isRequired ? Colors.red[700] : null,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: isRequired ? Colors.red[700] : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateString;
    }
  }

  Future<void> _startUpdate() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _downloadError = null;
      _apkPath = null;
    });

    try {
      final updateService = UpdateService();
      
      // Check device compatibility
      final isCompatible = await updateService.checkDeviceCompatibility(
        widget.updateInfo.minAndroidVersion,
      );

      if (!isCompatible) {
        setState(() {
          _downloadError = 'Device not compatible. Requires Android ${widget.updateInfo.minAndroidVersion}+';
          _isDownloading = false;
        });
        return;
      }

             // Check required permissions
       final hasPermissions = await updateService.checkRequiredPermissions();
       if (!hasPermissions) {
         setState(() {
           _downloadError = 'The app needs permission to install APK files. This is required for app updates. Please tap "Grant Permissions" below, or use "Open Settings" to manually enable the permission.';
           _isDownloading = false;
         });
         return;
       }

      // Download APK with proper file path tracking
      final downloadResult = await updateService.downloadApkWithPath(
        widget.updateInfo.downloadUrl,
        (progress) {
          setState(() => _downloadProgress = progress);
        },
      );

              if (downloadResult.success) {
          setState(() {
            _isDownloading = false;
            _apkPath = downloadResult.filePath;
          });
          
          if (_autoInstall) {
            // Show success message and auto-install
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Download completed! Starting automatic installation...',
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.green[700],
                duration: Duration(seconds: 3),
              ),
            );
            
            // Auto-install after successful download with a small delay for better UX
            await Future.delayed(Duration(milliseconds: 500));
            await _installUpdate();
          } else {
            // Show success message without auto-install
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Download completed! Tap "Install" to install the update.',
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.green[700],
                duration: Duration(seconds: 4),
              ),
            );
          }
        } else {
        setState(() {
          _downloadError = downloadResult.error ?? 'Download failed';
          _isDownloading = false;
        });
      }
          } catch (e) {
        String errorMessage = 'Error: $e';
        
        // Provide more helpful error messages
        if (e.toString().contains('Storage permission not granted')) {
          errorMessage = 'Storage access is required. Please grant storage permission in Settings > Apps > Project Nexus > Permissions';
        } else if (e.toString().contains('Could not access download directory')) {
          errorMessage = 'Unable to access download directory. Please check your device storage settings.';
        } else if (e.toString().contains('Download failed')) {
          errorMessage = 'Download failed. Please check your internet connection and try again.';
        }
        
        setState(() {
          _downloadError = errorMessage;
          _isDownloading = false;
        });
      }
  }

  Future<void> _installUpdate() async {
    if (_apkPath == null || _apkPath == 'Downloaded successfully') {
      setState(() {
        _downloadError = 'No APK file available for installation. Please try downloading again.';
      });
      return;
    }

    try {
      // Show installation progress
      setState(() {
        _isInstalling = true;
        _downloadError = null;
      });

      // Show installation message
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
                  'Installing update... Please wait.',
                  style: TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.blue[700],
          duration: Duration(seconds: 2),
        ),
      );

      final updateService = UpdateService();
      
      // Install APK using the tracked file path
      final success = await updateService.installApk(_apkPath!);
      
      if (success) {
        // Clear any existing snackbars
        ScaffoldMessenger.of(context).clearSnackBars();
        
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Installation started successfully! The app will update automatically.',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green[700],
            duration: Duration(seconds: 4),
          ),
        );
        
        // Automatically dismiss the dialog after successful installation
        await Future.delayed(Duration(seconds: 2));
        if (mounted) {
          Navigator.of(context).pop();
        }
      } else {
        setState(() {
          _isInstalling = false;
          _downloadError = 'Installation failed. Please try one of the following:\n\n1. Tap "Grant Permissions" to enable installation\n2. Go to Settings > Apps > Project Nexus > Install unknown apps\n3. Install manually from your downloads folder';
        });
      }
    } catch (e) {
      setState(() {
        _isInstalling = false;
        _downloadError = 'Installation error: $e';
      });
    }
  }

  // Request permissions and retry update
  Future<void> _requestPermissions() async {
    try {
      setState(() {
        _downloadError = 'Requesting permissions...';
      });

      final updateService = UpdateService();
      final hasPermissions = await updateService.requestAllPermissions();

      if (hasPermissions) {
        setState(() {
          _downloadError = null;
        });
        
        // Retry the update
        await _startUpdate();
      } else {
        setState(() {
          _downloadError = 'Permissions not granted. Please go to Settings > Apps > Project Nexus > Permissions and enable:\n\n• Install unknown apps\n• Storage (if on Android 10 or below)';
        });
      }
    } catch (e) {
      setState(() {
        _downloadError = 'Error requesting permissions: $e';
      });
    }
  }

  // Open app settings
  Future<void> _openAppSettings() async {
    try {
      final updateService = UpdateService();
      await updateService.openAppSettings();
    } catch (e) {
      setState(() {
        _downloadError = 'Error opening settings: $e';
      });
    }
  }

  // Open file manager to help with manual installation
  Future<void> _openFileManager() async {
    try {
      if (_apkPath != null && _apkPath != 'Downloaded successfully') {
        final updateService = UpdateService();
        final directory = await updateService.getDownloadDirectory();
        if (directory != null) {
          // Show a dialog with instructions for manual installation
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Manual Installation'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('To install manually:'),
                  const SizedBox(height: 8),
                  const Text('1. Open your file manager'),
                  const Text('2. Navigate to:'),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      directory.path,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('3. Find the APK file and tap it'),
                  const Text('4. Follow the installation prompts'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _downloadError = 'Error opening file manager: $e';
      });
    }
  }

  // Handle package conflicts specifically
  Future<void> _handlePackageConflict() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Package Conflict Resolution'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The update cannot be installed due to a package conflict. This usually happens when:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('• Different app signature (different developer/keystore)'),
            const Text('• Version downgrade attempt'),
            const Text('• Different package source'),
            const SizedBox(height: 16),
            const Text(
              'Solutions:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('1. Uninstall current app first, then install new version'),
            const Text('2. Ensure you\'re installing from the same source as original'),
            const Text('3. Contact app developer for proper update mechanism'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: const Text(
                '⚠️ Warning: Uninstalling will remove all app data!',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}
