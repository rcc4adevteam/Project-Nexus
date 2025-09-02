import 'package:flutter/material.dart';
import 'package:project_nexus/services/network_connectivity_service.dart';

class OfflineIndicator extends StatefulWidget {
  final VoidCallback? onRetry;
  final bool showRetryButton;
  
  const OfflineIndicator({
    super.key,
    this.onRetry,
    this.showRetryButton = true,
  });

  @override
  State<OfflineIndicator> createState() => _OfflineIndicatorState();
}

class _OfflineIndicatorState extends State<OfflineIndicator> {
  final NetworkConnectivityService _networkService = NetworkConnectivityService();
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
    _listenToConnectivityChanges();
  }

  Future<void> _checkConnectivity() async {
    try {
      final isOnline = await _networkService.checkConnectivity();
      if (mounted) {
        setState(() {
          _isOnline = isOnline;
        });
      }
    } catch (e) {
      print('OfflineIndicator: Error checking connectivity: $e');
    }
  }

  void _listenToConnectivityChanges() {
    _networkService.onConnectivityChanged.listen((isOnline) {
      if (mounted) {
        setState(() {
          _isOnline = isOnline;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isOnline) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.orange[100],
        border: Border(
          bottom: BorderSide(
            color: Colors.orange[300]!,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.wifi_off,
            color: Colors.orange[800],
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'You are currently offline. Some features may be limited.',
              style: TextStyle(
                color: Colors.orange[800],
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (widget.showRetryButton && widget.onRetry != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: () {
                _checkConnectivity();
                widget.onRetry?.call();
              },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Retry',
                style: TextStyle(
                  color: Colors.orange[800],
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    _networkService.dispose();
    super.dispose();
  }
}
