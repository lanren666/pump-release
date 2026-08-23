import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../config/app_color.dart';
import '../config/responsive_text.dart';
import '../l10n/app_localizations.dart';
import '../models/video_tutorial.dart';
import '../services/video_tutorial_catalog.dart';

class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({
    super.key,
    required this.video,
    required this.allVideos,
  });

  final VideoTutorial video;
  final List<VideoTutorial> allVideos;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    await _disposeControllers();

    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.video.videoUrl),
    );

    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      final chewie = ChewieController(
        videoPlayerController: controller,
        autoPlay: true,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
        showControls: true,
        materialProgressColors: ChewieProgressColors(
          playedColor: AppColor.primaryPurple,
          handleColor: AppColor.primaryPurple,
          bufferedColor: Colors.white38,
          backgroundColor: Colors.white24,
        ),
        placeholder: ColoredBox(
          color: Colors.black,
          child: Center(
            child: CircularProgressIndicator(
              color: AppColor.primaryPurple.withValues(alpha: 0.9),
            ),
          ),
        ),
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                errorMessage,
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ),
          );
        },
      );

      setState(() {
        _videoController = controller;
        _chewieController = chewie;
        _loading = false;
      });
    } catch (e) {
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = AppLocalizations.of(context)!.videoLoadFailed;
      });
    }
  }

  Future<void> _disposeControllers() async {
    _chewieController?.dispose();
    _chewieController = null;
    final videoController = _videoController;
    _videoController = null;
    await videoController?.dispose();
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  void _openVideo(VideoTutorial video) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => VideoPlayerPage(
          video: video,
          allVideos: widget.allVideos,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final upNext = widget.allVideos
        .where((video) => video.id != widget.video.id)
        .toList();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.black,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppColor.white,
        body: Column(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ColoredBox(
                color: Colors.black,
                child: _buildPlayerArea(l10n),
              ),
            ),
            Expanded(
              child: ListView(
                padding: ResponsiveText.symmetric(context, horizontal: 16, vertical: 16),
                children: [
                  Text(
                    VideoTutorialCatalog.title(l10n, widget.video.id),
                    style: ResponsiveText.title(
                      context,
                      fontWeight: FontWeight.w600,
                      color: AppColor.textPrimary,
                    ),
                  ),
                  SizedBox(height: ResponsiveText.getSize(context, 4)),
                  Text(
                    VideoTutorialCatalog.subtitle(l10n, widget.video.id),
                    style: ResponsiveText.bodySmall(
                      context,
                      color: AppColor.textSecondary,
                    ),
                  ),
                  SizedBox(height: ResponsiveText.getSize(context, 8)),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: ResponsiveText.getSize(context, 14),
                        color: AppColor.textSecondary,
                      ),
                      SizedBox(width: ResponsiveText.getSize(context, 4)),
                      Text(
                        _videoController != null &&
                                _videoController!.value.isInitialized
                            ? _formatDuration(_videoController!.value.duration)
                            : '—',
                        style: ResponsiveText.bodySmall(
                          context,
                          color: AppColor.textSecondary,
                        ),
                      ),
                      SizedBox(width: ResponsiveText.getSize(context, 12)),
                      Text(
                        l10n.videoOfficialSource,
                        style: ResponsiveText.bodySmall(
                          context,
                          color: AppColor.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: ResponsiveText.getSize(context, 16)),
                  Text(
                    VideoTutorialCatalog.description(l10n, widget.video.id),
                    style: ResponsiveText.body(
                      context,
                      color: const Color(0xFF6B6B6B),
                    ),
                  ),
                  if (upNext.isNotEmpty) ...[
                    SizedBox(height: ResponsiveText.getSize(context, 24)),
                    Text(
                      l10n.videoUpNext,
                      style: ResponsiveText.bodySmall(
                        context,
                        color: AppColor.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: ResponsiveText.getSize(context, 12)),
                    ...upNext.map(
                      (video) => _UpNextTile(
                        video: video,
                        onTap: () => _openVideo(video),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerArea(AppLocalizations l10n) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(
          color: AppColor.primaryPurple.withValues(alpha: 0.9),
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.white70, size: 40),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _initializePlayer,
                child: Text(l10n.videoRetry),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Chewie(controller: _chewieController!),
        Positioned(
          top: MediaQuery.of(context).padding.top + 4,
          left: 4,
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ],
    );
  }
}

class _UpNextTile extends StatelessWidget {
  const _UpNextTile({required this.video, required this.onTap});

  final VideoTutorial video;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: EdgeInsets.only(bottom: ResponsiveText.getSize(context, 8)),
      child: Material(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: ResponsiveText.symmetric(context, horizontal: 12, vertical: 10),
            child: Row(
              children: [
                _VideoThumbnail(video: video, compact: true),
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
      ),
    );
  }
}

class _VideoThumbnail extends StatelessWidget {
  const _VideoThumbnail({required this.video, this.compact = false});

  final VideoTutorial video;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final width = compact ? 72.0 : double.infinity;
    final height = compact ? 48.0 : null;

    return Container(
      width: width,
      height: height,
      constraints: compact ? null : const BoxConstraints(minHeight: 180),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(compact ? 8 : 16),
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
            size: compact ? 22 : 48,
          ),
          if (!compact)
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
              ),
              child: const Icon(
                Icons.play_arrow,
                color: Colors.white,
                size: 32,
              ),
            ),
        ],
      ),
    );
  }
}
