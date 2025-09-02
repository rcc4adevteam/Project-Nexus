import 'package:flutter/material.dart';

class StatusChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool elevated;

  const StatusChip({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    this.elevated = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.25)),
        boxShadow: elevated
            ? [
                BoxShadow(
                  color: color.withOpacity(0.12),
                  offset: const Offset(0, 6),
                  blurRadius: 14,
                ),
              ]
            : [],
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
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}


