import 'package:flutter/material.dart';

import '../config/app_color.dart';
import '../l10n/app_localizations.dart';
import '../models/video_tutorial.dart';

class VideoTutorialCatalog {
  VideoTutorialCatalog._();

  static const String gettingStartedUrl =
      'https://download.sporramom.com/videos/%E5%90%B8%E5%A5%B6%E5%99%A8.mp4';
  static const String assemblyUrl =
      'https://download.sporramom.com/videos/%E7%BB%84%E8%A3%85%E6%AD%A5%E9%AA%A4.mp4';
  static const String cleaningUrl =
      'https://download.sporramom.com/videos/%E6%8B%86%E5%8D%B8%E6%AD%A5%E9%AA%A4.mp4';

  static List<VideoTutorial> all() {
    return const [
      VideoTutorial(
        id: VideoTutorialId.gettingStarted,
        videoUrl: gettingStartedUrl,
        featured: true,
        thumbnailGradient: [Color(0xFFF5C842), Color(0xFFE8A850)],
        thumbnailIcon: Icons.smartphone_outlined,
      ),
      VideoTutorial(
        id: VideoTutorialId.assembly,
        videoUrl: assemblyUrl,
        featured: false,
        thumbnailGradient: [AppColor.primaryPurple, AppColor.deepPurple],
        thumbnailIcon: Icons.build_outlined,
      ),
      VideoTutorial(
        id: VideoTutorialId.cleaning,
        videoUrl: cleaningUrl,
        featured: false,
        thumbnailGradient: [Color(0xFFA4E8C0), Color(0xFF6DC89A)],
        thumbnailIcon: Icons.cleaning_services_outlined,
      ),
    ];
  }

  static String title(AppLocalizations l10n, VideoTutorialId id) {
    return switch (id) {
      VideoTutorialId.gettingStarted => l10n.videoGettingStartedTitle,
      VideoTutorialId.assembly => l10n.videoAssemblyTitle,
      VideoTutorialId.cleaning => l10n.videoCleaningTitle,
    };
  }

  static String subtitle(AppLocalizations l10n, VideoTutorialId id) {
    return switch (id) {
      VideoTutorialId.gettingStarted => l10n.videoGettingStartedSubtitle,
      VideoTutorialId.assembly => l10n.videoAssemblySubtitle,
      VideoTutorialId.cleaning => l10n.videoCleaningSubtitle,
    };
  }

  static String description(AppLocalizations l10n, VideoTutorialId id) {
    return switch (id) {
      VideoTutorialId.gettingStarted => l10n.videoGettingStartedDescription,
      VideoTutorialId.assembly => l10n.videoAssemblyDescription,
      VideoTutorialId.cleaning => l10n.videoCleaningDescription,
    };
  }
}
