import 'package:flutter/material.dart';

/// Medisom brand mark used across the app.
///
/// Uses the single source-of-truth asset:
/// `assets/images/Logo_medisom_icon.png`
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 64, this.semanticLabel = 'Medisom'});

  static const String assetPath = 'assets/images/Logo_medisom_icon.png';

  final double size;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    // The provided logo asset has a white background; we want the *entire* frame
    // to be white and follow the rounded container corners so it reads as a
    // single unified mark.
    final radius = BorderRadius.circular(size * 0.22);
    final padding = EdgeInsets.all(size * 0.14);

    return Semantics(
      label: semanticLabel,
      child: ClipRRect(
        borderRadius: radius,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: radius,
            border: Border.all(color: Colors.black.withValues(alpha: 0.08), width: 1),
          ),
          padding: padding,
          child: Image.asset(
            assetPath,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ),
      ),
    );
  }
}
