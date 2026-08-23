import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_color.dart';
import '../config/responsive_text.dart';
import '../l10n/app_localizations.dart';
import '../models/video_tutorial.dart';
import '../services/video_tutorial_catalog.dart';
import 'video_player_page.dart';

class VideoTutorialsPage extends StatelessWidget {
  const VideoTutorialsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final videos = VideoTutorialCatalog.all();
    final featured = videos.firstWhere((video) => video.featured);
    final listVideos = videos.where((video) => !video.featured).toList();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: AppColor.primaryPurple,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppColor.gradientStart,
        body: Column(
          children: [
            _buildHeader(context, l10n),
            Expanded(
              child: ListView(
                padding: ResponsiveText.symmetric(context, horizontal: 16, vertical: 16),
                children: [
                  Text(
                    l10n.videoFeatured,
                    style: ResponsiveText.bodySmall(
                      context,
                      color: const Color(0xFF6B6B6B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: ResponsiveText.getSize(context, 12)),
                  _FeaturedVideoCard(
                    video: featured,
                    onTap: () => _openPlayer(context, featured, videos),
                  ),
                  SizedBox(height: ResponsiveText.getSize(context, 24)),
                  Text(
                    '${l10n.videoCategoryFirstUse} · ${videos.length} ${videos.length == 1 ? l10n.videoCountOne : l10n.videoCountOther}',
                    style: ResponsiveText.bodySmall(
                      context,
                      color: const Color(0xFF6B6B6B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: ResponsiveText.getSize(context, 12)),
                  ...listVideos.map(
                    (video) => Padding(
                      padding: EdgeInsets.only(
                        bottom: ResponsiveText.getSize(context, 12),
                      ),
                      child: _VideoListTile(
                        video: video,
                        onTap: () => _openPlayer(context, video, videos),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AppLocalizations l10n) {
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        left: ResponsiveText.getSize(context, 8),
        right: ResponsiveText.getSize(context, 20),
        top: statusBarHeight + ResponsiveText.getSize(context, 8),
        bottom: ResponsiveText.getSize(context, 16),
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColor.primaryPurple, Color(0xFFB5A5E3)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: AppColor.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
              Text(
                l10n.videoTutorials,
                style: ResponsiveText.title(
                  context,
                  fontWeight: FontWeight.bold,
                  color: AppColor.white,
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveText.getSize(context, 8)),
          Padding(
            padding: EdgeInsets.only(left: ResponsiveText.getSize(context, 16)),
            child: Container(
              padding: ResponsiveText.symmetric(context, horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColor.white,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                l10n.videoCategoryFirstUse,
                style: ResponsiveText.bodySmall(
                  context,
                  color: AppColor.deepPurple,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openPlayer(
    BuildContext context,
    VideoTutorial video,
    List<VideoTutorial> allVideos,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VideoPlayerPage(video: video, allVideos: allVideos),
      ),
    );
  }
}

class _FeaturedVideoCard extends StatelessWidget {
  const _FeaturedVideoCard({required this.video, required this.onTap});

  final VideoTutorial video;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Material(
      color: AppColor.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: video.thumbnailGradient,
                      ),
                    ),
                    child: Icon(
                      video.thumbnailIcon,
                      color: Colors.white.withValues(alpha: 0.9),
                      size: 56,
                    ),
                  ),
                  Container(color: Colors.black.withValues(alpha: 0.08)),
                  Center(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                      ),
                      child: const Icon(
                        Icons.play_arrow,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: ResponsiveText.symmetric(context, horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    VideoTutorialCatalog.title(l10n, video.id),
                    style: ResponsiveText.smallTitle(
                      context,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: ResponsiveText.getSize(context, 4)),
                  Text(
                    VideoTutorialCatalog.subtitle(l10n, video.id),
                    style: ResponsiveText.bodySmall(
                      context,
                      color: AppColor.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoListTile extends StatelessWidget {
  const _VideoListTile({
    required this.video,
    required this.onTap,
  });

  final VideoTutorial video;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Material(
      color: AppColor.white,
      borderRadius: BorderRadius.circular(12),
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: ResponsiveText.symmetric(context, horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 80,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: video.thumbnailGradient,
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      video.thumbnailIcon,
                      color: Colors.white.withValues(alpha: 0.9),
                      size: 24,
                    ),
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: ResponsiveText.getSize(context, 12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      VideoTutorialCatalog.title(l10n, video.id),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: ResponsiveText.smallTitle(
                        context,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: ResponsiveText.getSize(context, 2)),
                    Text(
                      VideoTutorialCatalog.subtitle(l10n, video.id),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ResponsiveText.bodySmall(
                        context,
                        color: AppColor.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
