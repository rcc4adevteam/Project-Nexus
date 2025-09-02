import 'package:flutter/material.dart';

class SummaryBanner extends StatelessWidget {
  final String deploymentCode;
  final bool isOnline;
  final bool sessionActive;
  final int batteryLevel;
  final String signalStatus;
  final DateTime? lastUpdate;

  const SummaryBanner({
    super.key,
    required this.deploymentCode,
    required this.isOnline,
    required this.sessionActive,
    required this.batteryLevel,
    required this.signalStatus,
    required this.lastUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final Color onlineColor = isOnline ? Colors.green : Colors.red;
    final Color sessionColor = sessionActive ? Colors.green : Colors.red;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.badge, size: 18, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Deployment: $deploymentCode',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _buildChip(
                        context,
                        icon: isOnline ? Icons.wifi : Icons.wifi_off,
                        label: isOnline ? 'Online' : 'Offline',
                        color: onlineColor,
                      ),
                      _buildChip(
                        context,
                        icon: sessionActive ? Icons.verified_user : Icons.error,
                        label: sessionActive ? 'Session Active' : 'Session Lost',
                        color: sessionColor,
                      ),
                      _buildChip(
                        context,
                        icon: Icons.battery_full,
                        label: 'Battery $batteryLevel%',
                        color: batteryLevel > 50
                            ? Colors.green
                            : batteryLevel > 20
                                ? Colors.orange
                                : Colors.red,
                      ),
                      _buildChip(
                        context,
                        icon: Icons.signal_cellular_alt,
                        label: signalStatus.toUpperCase(),
                        color: _signalColor(signalStatus),
                      ),
                      if (lastUpdate != null)
                        _buildChip(
                          context,
                          icon: Icons.schedule,
                          label: 'Last ${lastUpdate!.toString().substring(11, 19)}',
                          color: Theme.of(context).colorScheme.primary,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _signalColor(String status) {
    switch (status.toLowerCase()) {
      case 'strong':
        return Colors.green;
      case 'weak':
        return Colors.orange;
      case 'poor':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Widget _buildChip(BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}


