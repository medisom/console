import 'package:flutter/material.dart';

class IFramePortalViewImpl extends StatelessWidget {
  const IFramePortalViewImpl({super.key, required this.url, this.onLoad, this.backgroundColor});

  final String url;
  final VoidCallback? onLoad;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
