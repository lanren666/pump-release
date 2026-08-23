import 'package:flutter/material.dart';

enum VideoTutorialId { gettingStarted, assembly, cleaning }

class VideoTutorial {
  const VideoTutorial({
    required this.id,
    required this.videoUrl,
    required this.featured,
    required this.thumbnailGradient,
    required this.thumbnailIcon,
  });

  final VideoTutorialId id;
  final String videoUrl;
  final bool featured;
  final List<Color> thumbnailGradient;
  final IconData thumbnailIcon;
}
