// ABOUTME: Service for extracting thumbnails from video files
// ABOUTME: Generates preview frames for video posts to include in NIP-71 events

import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:openvine/utils/unified_logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pro_video_editor/pro_video_editor.dart';

/// Service for extracting thumbnail images from video files
class VideoThumbnailService {
  static const int _thumbnailQuality = 75;
  static const Size _thumbnailSize = Size.square(640);

  static final _proVideoEditor = ProVideoEditor.instance;

  /// Extract a thumbnail from a video file at a specific timestamp
  ///
  /// [videoPath] - Path to the video file
  /// [timestamp] - Timestamp to extract thumbnail from (default: 500ms)
  /// [quality] - JPEG quality (1-100, default: 75)
  ///
  /// Returns the path to the generated thumbnail file
  static Future<String?> extractThumbnail({
    required String videoPath,
    // Extract frame at 500ms by default
    Duration timestamp = const Duration(milliseconds: 500),
    int quality = _thumbnailQuality,
  }) async {
    try {
      Log.debug(
        'Extracting thumbnail from video: $videoPath',
        name: 'VideoThumbnailService',
        category: LogCategory.video,
      );
      Log.debug(
        '⏱️ Timestamp: ${timestamp.inMilliseconds}ms',
        name: 'VideoThumbnailService',
        category: LogCategory.video,
      );

      // Verify video file exists
      final videoFile = File(videoPath);
      if (!videoFile.existsSync()) {
        Log.error(
          'Video file not found: $videoPath',
          name: 'VideoThumbnailService',
          category: LogCategory.video,
        );
        return null;
      }

      final destPath =
          '${(await getTemporaryDirectory()).path}/'
          'thumbnail_${DateTime.now().millisecondsSinceEpoch}.jpg';

      try {
        Log.debug(
          'Trying pro_video_editor plugin',
          name: 'VideoThumbnailService',
          category: LogCategory.video,
        );

        // TODO(@hm21): pro_video_editor currently returns thumbnails only as
        // in-memory Uint8List and does not create thumbnail files internally.
        // Until native file output is supported directly by pro_video_editor,
        // we persist the thumbnails to disk here as a temporary workaround.
        final thumbnail = await extractThumbnailBytes(
          videoPath: videoPath,
          timestamp: timestamp,
          quality: quality,
        );

        if (thumbnail == null) {
          throw Exception('Failed to extract thumbnail bytes from video');
        }
        final thumbnailFile = File(destPath);
        await thumbnailFile.writeAsBytes(thumbnail);

        final thumbnailSize = await thumbnailFile.length();
        Log.info(
          'Thumbnail generated with pro_video_editor:',
          name: 'VideoThumbnailService',
          category: LogCategory.video,
        );
        Log.debug(
          '  📸 Path: $destPath',
          name: 'VideoThumbnailService',
          category: LogCategory.video,
        );
        Log.debug(
          '  📦 Size: ${(thumbnailSize / 1024).toStringAsFixed(2)}KB',
          name: 'VideoThumbnailService',
          category: LogCategory.video,
        );
        return destPath;
      } catch (e) {
        Log.error(
          'Failed to generate thumbnail: $e',
          name: 'VideoThumbnailService',
          category: LogCategory.video,
        );
        return null;
      }
    } catch (e, stackTrace) {
      Log.error(
        'Thumbnail extraction error: $e',
        name: 'VideoThumbnailService',
        category: LogCategory.video,
      );
      Log.verbose(
        '📱 Stack trace: $stackTrace',
        name: 'VideoThumbnailService',
        category: LogCategory.video,
      );
      return null;
    }
  }

  /// Extract thumbnail as bytes (for direct upload without file)
  static Future<Uint8List?> extractThumbnailBytes({
    required String videoPath,
    Duration timestamp = const Duration(milliseconds: 500),
    int quality = _thumbnailQuality,
  }) async {
    try {
      Log.debug(
        'Extracting thumbnail bytes from video: $videoPath',
        name: 'VideoThumbnailService',
        category: LogCategory.video,
      );

      // Generate thumbnail file first
      final thumbnails = await _proVideoEditor.getThumbnails(
        ThumbnailConfigs(
          video: EditorVideo.file(videoPath),
          outputSize: _thumbnailSize,
          timestamps: [timestamp],
          outputFormat: .jpeg,
          // TODO(@hm21): Add an option to set a quality for thumbnails in
          // the pro_video_editor.
        ),
      );

      if (thumbnails.isEmpty) {
        Log.error(
          'Failed to generate thumbnail',
          name: 'VideoThumbnailService',
          category: LogCategory.video,
        );
        return null;
      }

      final thumbnail = thumbnails.first;

      Log.info(
        'Thumbnail bytes generated: '
        '${(thumbnail.lengthInBytes / 1024).toStringAsFixed(2)}KB',
        name: 'VideoThumbnailService',
        category: LogCategory.video,
      );
      return thumbnail;
    } catch (e) {
      Log.error(
        'Thumbnail bytes extraction error: $e',
        name: 'VideoThumbnailService',
        category: LogCategory.video,
      );
      return null;
    }
  }

  /// Generates multiple thumbnails from a video at different timestamps.
  ///
  /// Useful for presenting several candidate frames, such as for preview
  /// selection or cover image picking.
  ///
  /// If [timestamps] is not provided, thumbnails are extracted at **500ms,
  /// 1000ms, and 1500ms** by default. Extraction intentionally does not start
  /// at 0ms because many MP4 videos have no decodable frame at the beginning.
  /// The first keyframe typically appears after ~200–500ms.
  static Future<List<Uint8List>> extractMultipleThumbnails({
    required String videoPath,
    List<Duration>? timestamps,
  }) async {
    final timesToExtract =
        timestamps ??
        const [
          Duration(milliseconds: 500),
          Duration(milliseconds: 1000),
          Duration(milliseconds: 1500),
        ];

    final thumbnails = await _proVideoEditor.getThumbnails(
      ThumbnailConfigs(
        video: EditorVideo.file(videoPath),
        outputSize: _thumbnailSize,
        timestamps: timesToExtract,
        outputFormat: .jpeg,
      ),
    );

    Log.debug(
      '📱 Generated ${thumbnails.length} thumbnails',
      name: 'VideoThumbnailService',
      category: LogCategory.video,
    );
    return thumbnails;
  }

  /// Clean up temporary thumbnail files
  static Future<void> cleanupThumbnails(List<String> thumbnailPaths) async {
    for (final path in thumbnailPaths) {
      try {
        final file = File(path);
        if (file.existsSync()) {
          await file.delete();
          Log.debug(
            '📱️ Deleted thumbnail: $path',
            name: 'VideoThumbnailService',
            category: LogCategory.video,
          );
        }
      } catch (e) {
        Log.error(
          'Failed to delete thumbnail: $e',
          name: 'VideoThumbnailService',
          category: LogCategory.video,
        );
      }
    }
  }

  /// Get optimal thumbnail timestamp based on video duration
  static Duration getOptimalTimestamp(Duration videoDuration) {
    // Extract thumbnail from 10% into the video
    // This usually avoids black frames at the start
    final tenPercent = (videoDuration.inMilliseconds * 0.1).round();

    // But ensure it's at least 100ms and not more than 1 second
    return Duration(milliseconds: tenPercent.clamp(100, 1000));
  }
}
