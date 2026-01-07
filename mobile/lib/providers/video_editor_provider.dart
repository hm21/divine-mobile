// ABOUTME: Riverpod provider for managing video editor state with text overlays and export tracking
// ABOUTME: Exposes EditorNotifier for state mutations and reactive EditorState updates

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openvine/models/video_editor_state.dart';
import 'package:openvine/providers/clip_manager_provider.dart';
import 'package:openvine/providers/video_publish_provider.dart';
import 'package:openvine/router/nav_extensions.dart';
import 'package:openvine/widgets/video_editor/meta/video_editor_meta_sheet.dart';
import 'package:openvine/widgets/video_editor/video_editor_more_sheet.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pro_video_editor/pro_video_editor.dart';

final videoEditorProvider = NotifierProvider<VideoEditorNotifier, EditorState>(
  VideoEditorNotifier.new,
);

class VideoEditorNotifier extends Notifier<EditorState> {
  @override
  EditorState build() {
    return const EditorState();
  }

  void selectClip(int index) {
    final clipManager = ref.read(clipManagerProvider.notifier);

    // Calculate offset from all previous clips
    final offset = clipManager.clips
        .take(index)
        .fold(Duration.zero, (sum, clip) => sum + clip.duration);

    state = state.copyWith(
      currentClipIndex: index,
      isPlaying: false,
      currentPosition: offset,
    );
  }

  void startClipReordering() {
    state = state.copyWith(isReordering: true);
  }

  void stopClipReordering() {
    state = state.copyWith(isReordering: false, isOverDeleteZone: false);
  }

  void setOverDeleteZone(bool isOver) {
    state = state.copyWith(isOverDeleteZone: isOver);
  }

  void startClipEditing() {
    state = state.copyWith(isEditing: true);
  }

  void stopClipEditing() {
    state = state.copyWith(isEditing: false);
  }

  void toggleClipEditing() {
    state = state.copyWith(isEditing: !state.isEditing);
  }

  void pauseVideo() {
    state = state.copyWith(isPlaying: false);
  }

  void togglePlayPause() {
    state = state.copyWith(isPlaying: !state.isPlaying);
  }

  void toggleMute() {
    state = state.copyWith(isMuted: !state.isMuted);
  }

  void reset() {
    state = const EditorState();
  }

  void updatePosition(Duration position) {
    final clipManager = ref.read(clipManagerProvider.notifier);

    // Calculate offset from all previous clips
    final offset = clipManager.clips
        .take(state.currentClipIndex)
        .fold(Duration.zero, (sum, clip) => sum + clip.duration);

    state = state.copyWith(currentPosition: offset + position);
  }

  void close() {
    // Reset state or perform cleanup if needed
  }

  void done(BuildContext context) async {
    state = state.copyWith(isProcessing: true);

    final completer = Completer<String?>();

    unawaited(_renderVideo(completer));

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF101111),
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const VideoEditorMetaSheet(
        // draftId: '',
      ),
    );

    final outputPath = await completer.future;

    final validToPublish = outputPath != null;

    final metaData = validToPublish
        ? await ProVideoEditor.instance.getMetadata(
            EditorVideo.file(outputPath),
          )
        : null;

    state = state.copyWith(isProcessing: false);

    if (!validToPublish || !context.mounted) return;

    ref.read(videoPublishProvider.notifier)
      ..reset()
      ..setVideoData(video: EditorVideo.file(outputPath), metadata: metaData!);

    await context.pushVideoPublish();
  }

  void showMoreOptions(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF101111),
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: .vertical(top: .circular(32)),
      ),
      builder: (context) => const VideoEditorMoreSheet(),
    );
  }

  Future<void> _renderVideo(Completer<String?> completer) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final outputPath =
          '${tempDir.path}/divine_${DateTime.now().microsecondsSinceEpoch}.mp4';

      final clipManager = ref.read(clipManagerProvider.notifier);
      final clips = clipManager.clips;

      final videoSegments = clips
          .map((clip) => VideoSegment(video: clip.video))
          .toList();

      final metaData = await ProVideoEditor.instance.getMetadata(
        videoSegments.first.video,
      );
      final resolution = metaData.resolution;

      double cropX, cropY, cropWidth, cropHeight;

      switch (clips.first.aspectRatio) {
        case .square:
          // Center crop to 1:1 (minimum dimension)
          final minDimension = resolution.width < resolution.height
              ? resolution.width
              : resolution.height;
          cropWidth = minDimension;
          cropHeight = minDimension;
          cropX = (resolution.width - cropWidth) / 2;
          cropY = (resolution.height - cropHeight) / 2;

        case .vertical:
          // Center crop to 9:16 (portrait)
          final inputAspectRatio = resolution.width / resolution.height;
          const targetAspectRatio = 9.0 / 16.0;

          if (inputAspectRatio > targetAspectRatio) {
            // Input is wider than 9:16 - crop width, keep height
            cropHeight = resolution.height;
            cropWidth = cropHeight * targetAspectRatio;
            cropX = (resolution.width - cropWidth) / 2;
            cropY = 0;
          } else {
            // Input is taller than 9:16 - keep width, crop height
            cropWidth = resolution.width;
            cropHeight = cropWidth / targetAspectRatio;
            cropX = 0;
            cropY = (resolution.height - cropHeight) / 2;
          }
      }

      final task = VideoRenderData(
        videoSegments: videoSegments,
        endTime: const Duration(milliseconds: 6_300),
        transform: ExportTransform(
          x: cropX.round(),
          y: cropY.round(),
          width: cropWidth.round(),
          height: cropHeight.round(),
        ),
      );

      await ProVideoEditor.instance.renderVideoToFile(outputPath, task);
      state = state.copyWith(isProcessing: false);

      completer.complete(outputPath);
    } on RenderCanceledException {
      completer.complete(null);
    } catch (e) {
      completer.complete(null);
    }
  }
}
