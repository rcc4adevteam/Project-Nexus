import 'package:flutter/material.dart';
import '../services/responsive_ui_service.dart';

/// Auto-sizing text widget that adjusts font size to fit available space
class AutoSizeText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final double minFontSize;
  final double maxFontSize;
  final double stepGranularity;
  final bool presetFontSizes;
  final List<double>? fontSizes;

  const AutoSizeText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.minFontSize = 12.0,
    this.maxFontSize = double.infinity,
    this.stepGranularity = 1.0,
    this.presetFontSizes = false,
    this.fontSizes,
  });

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ?? Theme.of(context).textTheme.bodyMedium!;
    final baseFontSize = baseStyle.fontSize ?? 14.0;
    
    // Get responsive font size
    final responsiveFontSize = ResponsiveUIService.getResponsiveFontSize(
      context: context,
      baseFontSize: baseFontSize,
      minSize: minFontSize,
      maxSize: maxFontSize == double.infinity ? baseFontSize * 2 : maxFontSize,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        return _buildAutoSizedText(context, constraints, responsiveFontSize, baseStyle);
      },
    );
  }

  Widget _buildAutoSizedText(
    BuildContext context,
    BoxConstraints constraints,
    double startFontSize,
    TextStyle baseStyle,
  ) {
    double fontSize = startFontSize;
    
    // Use preset font sizes if provided
    if (presetFontSizes && fontSizes != null && fontSizes!.isNotEmpty) {
      fontSize = _findBestPresetFontSize(context, constraints, baseStyle);
    } else {
      fontSize = _findBestFontSize(context, constraints, baseStyle, startFontSize);
    }

    return Text(
      text,
      style: baseStyle.copyWith(fontSize: fontSize),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.ellipsis,
    );
  }

  double _findBestFontSize(
    BuildContext context,
    BoxConstraints constraints,
    TextStyle baseStyle,
    double startFontSize,
  ) {
    double fontSize = startFontSize;
    
    // Binary search for optimal font size
    double minSize = minFontSize;
    double maxSize = maxFontSize == double.infinity ? startFontSize * 2 : maxFontSize;
    
    while (maxSize - minSize > stepGranularity) {
      fontSize = (minSize + maxSize) / 2;
      
      if (_doesTextFit(context, constraints, baseStyle.copyWith(fontSize: fontSize))) {
        minSize = fontSize;
      } else {
        maxSize = fontSize;
      }
    }
    
    return minSize;
  }

  double _findBestPresetFontSize(
    BuildContext context,
    BoxConstraints constraints,
    TextStyle baseStyle,
  ) {
    final sortedSizes = List<double>.from(fontSizes!)..sort((a, b) => b.compareTo(a));
    
    for (double size in sortedSizes) {
      if (size >= minFontSize && 
          size <= maxFontSize && 
          _doesTextFit(context, constraints, baseStyle.copyWith(fontSize: size))) {
        return size;
      }
    }
    
    return minFontSize;
  }

  bool _doesTextFit(BuildContext context, BoxConstraints constraints, TextStyle style) {
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: maxLines,
      textDirection: TextDirection.ltr,
      textAlign: textAlign ?? TextAlign.start,
    );
    
    textPainter.layout(maxWidth: constraints.maxWidth);
    
    return textPainter.size.height <= constraints.maxHeight &&
           textPainter.size.width <= constraints.maxWidth;
  }
}