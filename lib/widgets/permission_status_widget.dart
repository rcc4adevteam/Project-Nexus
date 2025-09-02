import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/responsive_ui_service.dart';
import 'auto_size_text.dart';

class PermissionStatusWidget extends StatelessWidget {
  final PermissionStatus status;
  final String title;
  final String description;
  final VoidCallback? onRequest;

  const PermissionStatusWidget({
    super.key,
    required this.status,
    required this.title,
    required this.description,
    this.onRequest,
  });

  Color get statusColor {
    switch (status) {
      case PermissionStatus.granted:
        return Colors.green;
      case PermissionStatus.denied:
        return Colors.orange;
      case PermissionStatus.permanentlyDenied:
        return Colors.red;
      case PermissionStatus.restricted:
        return Colors.purple;
      case PermissionStatus.limited:
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }

  IconData get statusIcon {
    switch (status) {
      case PermissionStatus.granted:
        return Icons.check_circle;
      case PermissionStatus.denied:
        return Icons.warning;
      case PermissionStatus.permanentlyDenied:
        return Icons.block;
      case PermissionStatus.restricted:
        return Icons.lock;
      case PermissionStatus.limited:
        return Icons.info;
      default:
        return Icons.help;
    }
  }

  String get statusText {
    switch (status) {
      case PermissionStatus.granted:
        return 'GRANTED';
      case PermissionStatus.denied:
        return 'DENIED';
      case PermissionStatus.permanentlyDenied:
        return 'PERMANENTLY DENIED';
      case PermissionStatus.restricted:
        return 'RESTRICTED';
      case PermissionStatus.limited:
        return 'LIMITED';
      default:
        return 'UNKNOWN';
    }
  }

  // Removed per-item action button; items now display status only.

  bool get _isCritical {
    return title.toLowerCase().contains('background') || 
           title.toLowerCase().contains('location') ||
           title.toLowerCase().contains('battery') ||
           title.toLowerCase().contains('notification');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: context.responsiveMargin(12.0),
      child: Card(
        elevation: _isCritical ? 6 : 4,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: _isCritical && status != PermissionStatus.granted
                ? Border.all(color: statusColor.withOpacity(0.3), width: 2)
                : null,
          ),
          child: Padding(
            padding: context.responsivePadding(16.0),
            child: Column(
              children: [
                // Main content row with proper alignment
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icon container with fixed sizing
                    Container(
                      width: context.responsiveFont(52.0),
                      height: context.responsiveFont(52.0),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: statusColor.withOpacity(0.3),
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        statusIcon, 
                        color: statusColor, 
                        size: context.responsiveFont(28.0),
                      ),
                    ),
                    SizedBox(width: 12),
                    
                    // Content section with proper flex layout
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title row with proper alignment
                          Row(
                            children: [
                              Expanded(
                                child: AutoSizeText(
                                  title,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: _isCritical ? statusColor : null,
                                  ),
                                  maxLines: 2,
                                  minFontSize: context.responsiveFont(12.0),
                                  maxFontSize: context.responsiveFont(16.0),
                                ),
                              ),
                              SizedBox(width: 8),
                              // Critical badge
                              if (_isCritical && status != PermissionStatus.granted)
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                                  ),
                                  child: AutoSizeText(
                                    'CRITICAL',
                                    style: TextStyle(
                                      color: Colors.red,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    minFontSize: context.responsiveFont(6.0),
                                    maxFontSize: context.responsiveFont(10.0),
                                  ),
                                ),
                            ],
                          ),
                          SizedBox(height: 4),
                          
                          // Status badge with proper alignment
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: AutoSizeText(
                                statusText,
                                style: TextStyle(
                                  color: statusColor,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                minFontSize: context.responsiveFont(8.0),
                                maxFontSize: context.responsiveFont(12.0),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                  ],
                ),
                
                // Description section with proper spacing
                if (status != PermissionStatus.granted) ...[
                  SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: statusColor.withOpacity(0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              status == PermissionStatus.permanentlyDenied 
                                  ? Icons.warning 
                                  : Icons.info, 
                              color: statusColor, 
                              size: 18,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (status == PermissionStatus.permanentlyDenied) ...[
                                    AutoSizeText(
                                      'Permission Permanently Denied',
                                      style: TextStyle(
                                        color: statusColor,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 1,
                                      minFontSize: context.responsiveFont(12.0),
                                      maxFontSize: context.responsiveFont(16.0),
                                    ),
                                    SizedBox(height: 4),
                                    AutoSizeText(
                                      'Go to Settings > Apps > This App > Permissions to enable manually.',
                                      style: TextStyle(
                                        color: statusColor.withOpacity(0.8),
                                      ),
                                      maxLines: 2,
                                      minFontSize: context.responsiveFont(10.0),
                                      maxFontSize: context.responsiveFont(14.0),
                                    ),
                                    SizedBox(height: 8),
                                  ],
                                  AutoSizeText(
                                    description,
                                    style: TextStyle(
                                      color: statusColor.withOpacity(0.9),
                                    ),
                                    maxLines: 3,
                                    minFontSize: context.responsiveFont(10.0),
                                    maxFontSize: context.responsiveFont(14.0),
                                  ),
                                  
                                  // Special instructions for background location
                                  if (title.toLowerCase().contains('background')) ...[
                                    SizedBox(height: 8),
                                    Container(
                                      width: double.infinity,
                                      padding: EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.amber.withOpacity(0.3)),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          AutoSizeText(
                                            'Android 12+ Instructions:',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.amber[800],
                                            ),
                                            maxLines: 1,
                                            minFontSize: context.responsiveFont(10.0),
                                            maxFontSize: context.responsiveFont(14.0),
                                          ),
                                          SizedBox(height: 4),
                                          AutoSizeText(
                                            '1. First grant basic location permission\n'
                                            '2. Then select "Allow all the time" for background\n'
                                            '3. If settings open, navigate to Location permissions\n'
                                            '4. Change from "While using app" to "Allow all the time"',
                                            style: TextStyle(
                                              color: Colors.amber[800],
                                            ),
                                            maxLines: 6,
                                            minFontSize: context.responsiveFont(8.0),
                                            maxFontSize: context.responsiveFont(12.0),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                
                // Success message for granted permissions
                if (status == PermissionStatus.granted) ...[
                  SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: AutoSizeText(
                            'Permission granted successfully!',
                            style: TextStyle(
                              color: Colors.green[800],
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 2,
                            minFontSize: context.responsiveFont(10.0),
                            maxFontSize: context.responsiveFont(14.0),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}