import 'package:flutter/material.dart';
import '../services/responsive_ui_service.dart';
import 'auto_size_text.dart';

class MetricCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final String value;
  final String subtitle;
  final bool isRealTime;
  final VoidCallback? onTap;

  const MetricCard({
    super.key,
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.subtitle,
    this.isRealTime = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Check card types for special styling
    final isSessionCard = title.toLowerCase().contains('session');
    final isSignalStatusCard = title.toLowerCase().contains('signal');
    
    return Card(
      margin: context.responsiveMargin(4.0),
      elevation: isSessionCard ? 8.0 : 5.0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16.0),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                iconColor.withOpacity(isSessionCard ? 0.08 : 0.04),
                iconColor.withOpacity(isSessionCard ? 0.02 : 0.01),
              ],
            ),
          ),
          child: Padding(
            padding: context.responsivePadding(12.0),
            child: _buildCardContent(context, isSessionCard, isSignalStatusCard),
          ),
        ),
      ),
    );
  }

  Widget _buildCardContent(BuildContext context, bool isSessionCard, bool isSignalStatusCard) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate available space
        final iconContainerSize = context.responsiveFont(36.0);
        final spacing = context.responsiveFont(8.0);
        
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildIconContainer(context, iconContainerSize, isSessionCard),
            SizedBox(width: spacing),
            Expanded(
              child: _buildContentColumn(context, isSessionCard, isSignalStatusCard),
            ),
          ],
        );
      },
    );
  }

  Widget _buildIconContainer(BuildContext context, double size, bool isSessionCard) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(context.responsiveFont(6.0)),
      decoration: BoxDecoration(
        color: iconColor.withOpacity(isSessionCard ? 0.18 : 0.12),
        shape: BoxShape.circle,
        border: Border.all(
          color: iconColor.withOpacity(0.25),
          width: 1.0,
        ),
      ),
      child: Icon(
        icon,
        color: iconColor,
        size: context.responsiveFont(20.0),
      ),
    );
  }

  Widget _buildContentColumn(BuildContext context, bool isSessionCard, bool isSignalStatusCard) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildTitleRow(context, isSessionCard),
        SizedBox(height: context.responsiveFont(2.0)),
        _buildValueText(context, isSessionCard, isSignalStatusCard),
        if (subtitle.isNotEmpty) ...[
          SizedBox(height: context.responsiveFont(1.0)),
          _buildSubtitleText(context, isSessionCard),
        ],
      ],
    );
  }

  Widget _buildTitleRow(BuildContext context, bool isSessionCard) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: AutoSizeText(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: isSessionCard ? iconColor : null,
            ),
            maxLines: 1,
            minFontSize: context.responsiveFont(8.0),
            maxFontSize: context.responsiveFont(12.0),
          ),
        ),
        if (isRealTime) ...[
          SizedBox(width: 4.0),
          _buildBadge(context, isSessionCard),
        ],
      ],
    );
  }

  Widget _buildBadge(BuildContext context, bool isSessionCard) {
    final text = isSessionCard ? '5s' : 'LIVE';
    final badgeColor = isSessionCard ? iconColor : Colors.green;
    
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: context.responsiveFont(3.0),
        vertical: context.responsiveFont(1.0),
      ),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.18),
        borderRadius: BorderRadius.circular(context.responsiveFont(6.0)),
        border: Border.all(color: badgeColor.withOpacity(0.3), width: 0.8),
      ),
      child: AutoSizeText(
        text,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: badgeColor,
        ),
        maxLines: 1,
        minFontSize: context.responsiveFont(4.0),
        maxFontSize: context.responsiveFont(8.0),
      ),
    );
  }

  Widget _buildValueText(BuildContext context, bool isSessionCard, bool isSignalStatusCard) {
    // Special handling for different value types
    final isLongText = value.length > 15;
    
    double baseFontSize;
    if (isSignalStatusCard) {
      baseFontSize = 14.0;
    } else if (isLongText) {
      baseFontSize = 11.0;
    } else {
      baseFontSize = 13.0;
    }

    return AutoSizeText(
      value,
      style: TextStyle(
        fontWeight: FontWeight.w800,
        height: 1.15,
        color: isSessionCard ? iconColor : null,
      ),
      maxLines: isLongText ? 2 : 1,
      minFontSize: context.responsiveFont(8.0),
      maxFontSize: context.responsiveFont(baseFontSize),
      textAlign: TextAlign.start,
    );
  }

  Widget _buildSubtitleText(BuildContext context, bool isSessionCard) {
    return AutoSizeText(
      subtitle,
      style: TextStyle(
        color: isSessionCard 
            ? iconColor.withOpacity(0.7)
            : Colors.grey[700],
        fontWeight: isSessionCard ? FontWeight.w600 : FontWeight.w400,
      ),
      maxLines: 2,
      minFontSize: context.responsiveFont(5.0),
      maxFontSize: context.responsiveFont(8.0),
    );
  }
}