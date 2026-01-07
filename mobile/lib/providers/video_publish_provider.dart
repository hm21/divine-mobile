// ABOUTME: Riverpod provider for managing video publish screen state
// ABOUTME: Controls playback, mute state, and position tracking

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openvine/models/recording_clip.dart';
import 'package:openvine/models/video_publish/video_publish_state.dart';
import 'package:openvine/models/video_publish_state.dart';
import 'package:openvine/models/vine_draft.dart';
import 'package:openvine/providers/video_editor_provider.dart';
import 'package:openvine/router/nav_extensions.dart';
import 'package:openvine/services/draft_storage_service.dart';
import 'package:openvine/services/video_publish/video_publish_service.dart';
import 'package:openvine/utils/unified_logger.dart';
import 'package:pro_video_editor/pro_video_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:models/models.dart' as model show AspectRatio;

/// Provider for video publish screen state management.
final videoPublishProvider =
    NotifierProvider<VideoPublishNotifier, VideoPublishProviderState>(
      VideoPublishNotifier.new,
    );

/// Manages video publish screen state including playback and position.
class VideoPublishNotifier extends Notifier<VideoPublishProviderState> {
  String? _draftId;
  bool _isPublishing = false;
  final publishService = VideoPublishService();

  @override
  VideoPublishProviderState build() {
    return const VideoPublishProviderState();
  }

  /// Toggles between play and pause states.
  void togglePlayPause() {
    final newState = !state.isPlaying;
    state = state.copyWith(isPlaying: newState);

    Log.info(
      '${newState ? '▶️' : '⏸️'} Video ${newState ? 'playing' : 'paused'}',
      name: 'VideoPublishNotifier',
      category: .video,
    );
  }

  /// Sets the playing state.
  void setPlaying(bool isPlaying) {
    state = state.copyWith(isPlaying: isPlaying);

    Log.info(
      '${isPlaying ? '▶️' : '⏸️'} Video playback set to '
      '${isPlaying ? 'playing' : 'paused'}',
      name: 'VideoPublishNotifier',
      category: .video,
    );
  }

  /// Toggles mute state.
  void toggleMute() {
    final newState = !state.isMuted;
    state = state.copyWith(isMuted: newState);

    Log.info(
      '${newState ? '🔇' : '🔊'} Video ${newState ? 'muted' : 'unmuted'}',
      name: 'VideoPublishNotifier',
      category: .video,
    );
  }

  /// Sets the muted state.
  void setMuted(bool isMuted) {
    state = state.copyWith(isMuted: isMuted);

    Log.info(
      '${isMuted ? '🔇' : '🔊'} Video audio set to '
      '${isMuted ? 'muted' : 'unmuted'}',
      name: 'VideoPublishNotifier',
      category: .video,
    );
  }

  /// Updates current playback position.
  void updatePosition(Duration position) {
    state = state.copyWith(currentPosition: position);
  }

  /// Sets total video duration.
  void setDuration(Duration duration) {
    state = state.copyWith(totalDuration: duration);

    Log.info(
      '⏱️ Video duration set: ${duration.inSeconds}s',
      name: 'VideoPublishNotifier',
      category: .video,
    );
  }

  /// Sets video data and metadata for publishing.
  void setVideoData({
    required EditorVideo video,
    required VideoMetadata metadata,
    required model.AspectRatio aspectRatio,
  }) {
    state = state.copyWith(
      clip: RecordingClip(
        id: 'clip-${DateTime.now()}',
        video: video,
        duration: metadata.duration,
        recordedAt: .now(),
        aspectRatio: aspectRatio,
      ),
    );

    Log.info(
      '📹 Video data loaded: ${metadata.resolution.width}x'
      '${metadata.resolution.height}',
      name: 'VideoPublishNotifier',
      category: .video,
    );
  }

  void setUploadProgress(double value) {
    state = state.copyWith(uploadProgress: value);
  }

  void setPublishState(VideoPublishState value) {
    state = state.copyWith(publishState: value);
  }

  void setDraftId(String id) {
    _draftId = id;
  }

  Future<VineDraft> getDraft() async {
    VineDraft? draft;

    if (_draftId != null && _draftId!.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final draftService = DraftStorageService(prefs);
      draft = await draftService.getDraftById(_draftId!);
    }

    draft ??= VineDraft.create(
      clips: [],
      title: '',
      description: '',
      hashtags: [],
      selectedApproach: 'video',
    );

    final meta = ref.read(videoEditorProvider.notifier).metadata;

    /// We update the stored draft, with the current video-editor meta values.
    final resultDraft = draft.copyWith(
      clips: [state.clip!],
      title: meta?.title,
      description: meta?.description,
      hashtags: meta?.hashtags,
      allowAudioReuse: meta?.allowAudioReuse,
      expireTime: meta?.expireTime,
    );

    if (resultDraft.nativeProof == null) {
      // TODO(@hm21):
    }

    return resultDraft;
  }

  Future<void> publishVideo(BuildContext context) async {
    if (_isPublishing) return;
    _isPublishing = true;

    // Stop video playback when publishing starts
    setPlaying(false);
    Log.info('📝 Paused video playback for publishing', category: .video);

    await publishService.publishVideo(
      ref: ref,
      context: context,
      draft: await getDraft(),
    );
    _isPublishing = false;

    /// TODO(@hm21): Logic from before but will that pop the other screens?
    /// To prevent android back-button?
    context.goMyProfile();
  }

  /// Resets state to initial values.
  void reset() {
    state = const VideoPublishProviderState();

    Log.info(
      '🔄 Video publish state reset',
      name: 'VideoPublishNotifier',
      category: .video,
    );
  }
}
