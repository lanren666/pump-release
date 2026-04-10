import 'package:flutter/material.dart';

class ResponsiveText {
  ResponsiveText._();

  static const double _referenceWidth = 500;

  static double _getScreenWidth(BuildContext context) {
    return MediaQuery.of(context).size.width;
  }

  static double _getScaleFactor(BuildContext context) {
    final screenWidth = _getScreenWidth(context);
    if (screenWidth >= _referenceWidth) {
      return 1.0;
    }
    return (screenWidth / _referenceWidth).clamp(0.7, 1.0);
  }

  static double getFontSize(BuildContext context, double baseFontSize) {
    return baseFontSize * _getScaleFactor(context);
  }

  static double getSize(BuildContext context, double baseSize) {
    return baseSize * _getScaleFactor(context);
  }

  static EdgeInsets padding(
    BuildContext context, {
    double? all,
    double? horizontal,
    double? vertical,
    double? top,
    double? bottom,
    double? left,
    double? right,
  }) {
    final scale = _getScaleFactor(context);
    if (all != null) {
      return EdgeInsets.all(all * scale);
    }
    return EdgeInsets.only(
      left: (left ?? horizontal ?? 0) * scale,
      right: (right ?? horizontal ?? 0) * scale,
      top: (top ?? vertical ?? 0) * scale,
      bottom: (bottom ?? vertical ?? 0) * scale,
    );
  }

  static EdgeInsets symmetric(
    BuildContext context, {
    double? horizontal,
    double? vertical,
  }) {
    final scale = _getScaleFactor(context);
    return EdgeInsets.symmetric(
      horizontal: (horizontal ?? 0) * scale,
      vertical: (vertical ?? 0) * scale,
    );
  }

  static TextStyle style(
    BuildContext context, {
    required double fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
    double? letterSpacing,
    TextDecoration? decoration,
  }) {
    return TextStyle(
      fontSize: getFontSize(context, fontSize),
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
      decoration: decoration,
    );
  }

  static TextStyle huge(
    BuildContext context, {
    Color? color,
    FontWeight? fontWeight,
  }) {
    return style(context, fontSize: 40, color: color, fontWeight: fontWeight);
  }

  static TextStyle extraLarge(
    BuildContext context, {
    Color? color,
    FontWeight? fontWeight,
  }) {
    return style(context, fontSize: 32, color: color, fontWeight: fontWeight);
  }

  static TextStyle mediumLarge(
    BuildContext context, {
    Color? color,
    FontWeight? fontWeight,
  }) {
    return style(context, fontSize: 28, color: color, fontWeight: fontWeight);
  }

  static TextStyle large(
    BuildContext context, {
    Color? color,
    FontWeight? fontWeight,
  }) {
    return style(context, fontSize: 24, color: color, fontWeight: fontWeight);
  }

  static TextStyle title(
    BuildContext context, {
    Color? color,
    FontWeight? fontWeight,
  }) {
    return style(context, fontSize: 20, color: color, fontWeight: fontWeight);
  }

  static TextStyle smallTitle(
    BuildContext context, {
    Color? color,
    FontWeight? fontWeight,
  }) {
    return style(context, fontSize: 18, color: color, fontWeight: fontWeight);
  }

  static TextStyle body(
    BuildContext context, {
    Color? color,
    FontWeight? fontWeight,
  }) {
    return style(context, fontSize: 16, color: color, fontWeight: fontWeight);
  }

  static TextStyle bodySmall(
    BuildContext context, {
    Color? color,
    FontWeight? fontWeight,
    double? height,
  }) {
    return style(
      context,
      fontSize: 14,
      color: color,
      fontWeight: fontWeight,
      height: height,
    );
  }

  static TextStyle caption(
    BuildContext context, {
    Color? color,
    FontWeight? fontWeight,
    double? height,
  }) {
    return style(
      context,
      fontSize: 13,
      color: color,
      fontWeight: fontWeight,
      height: height,
    );
  }

  static TextStyle captionSmall(
    BuildContext context, {
    Color? color,
    FontWeight? fontWeight,
  }) {
    return style(context, fontSize: 12, color: color, fontWeight: fontWeight);
  }

  static TextStyle tiny(
    BuildContext context, {
    Color? color,
    FontWeight? fontWeight,
  }) {
    return style(context, fontSize: 10, color: color, fontWeight: fontWeight);
  }

  static TextStyle extraSmall(
    BuildContext context, {
    Color? color,
    FontWeight? fontWeight,
  }) {
    return style(context, fontSize: 11, color: color, fontWeight: fontWeight);
  }
}
