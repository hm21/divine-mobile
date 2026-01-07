// ABOUTME: Riverpod provider for Clip Manager state management
// ABOUTME: Manages recorded video clips with modern Notifier pattern

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:models/models.dart' as model show AspectRatio;
import 'package:openvine/models/clip_manager_state.dart';
import 'package:openvine/models/recording_clip.dart';
import 'package:openvine/models/saved_clip.dart';
import 'package:openvine/models/vine_draft.dart';
import 'package:openvine/providers/app_providers.dart';
import 'package:openvine/providers/video_editor_provider.dart';
import 'package:openvine/screens/clip_library_screen.dart';
import 'package:openvine/services/draft_storage_service.dart';
import 'package:openvine/theme/vine_theme.dart';
import 'package:openvine/utils/unified_logger.dart';
import 'package:pro_video_editor/pro_video_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

final clipManagerProvider =
    NotifierProvider<ClipManagerNotifier, ClipManagerState>(
      ClipManagerNotifier.new,
    );

class ClipManagerNotifier extends Notifier<ClipManagerState> {
  static const Duration maxDuration = Duration(milliseconds: 6_300);

  int _clipCounter = 0;
  Timer? _recordingDurationTimer;
  final _recordStopwatch = Stopwatch();
  final List<RecordingClip> _clips = [];
  List<RecordingClip> get clips => List.unmodifiable(_clips);

  @override
  ClipManagerState build() {
    ref.onDispose(() {
      _recordingDurationTimer?.cancel();
      _recordStopwatch.stop();
      _clips.clear();
    });
    return ClipManagerState();
  }

  /// Start recording timer for active clip duration tracking.
  void startRecording() {
    _recordStopwatch
      ..reset()
      ..start();

    Log.debug(
      '▶️  Recording timer started',
      name: 'ClipManagerNotifier',
      category: .video,
    );

    // Update activeRecordingDuration every 16ms (~60fps).
    // We ONLY rebuild with that logic, the progress inside of the segment-bar.
    _recordingDurationTimer = Timer.periodic(const Duration(milliseconds: 16), (
      _,
    ) {
      if (_recordStopwatch.isRunning) {
        state = state.copyWith(
          activeRecordingDuration: _recordStopwatch.elapsed,
        );
      }
    });
  }

  /// Stop recording timer and freeze duration.
  void stopRecording() {
    _recordStopwatch.stop();
    _recordingDurationTimer?.cancel();

    Log.debug(
      '⏸️  Recording timer stopped at ${_recordStopwatch.elapsed.inMilliseconds}ms',
      name: 'ClipManagerNotifier',
      category: .video,
    );
  }

  /// Reset recording stopwatch to zero.
  void resetRecording() {
    _recordStopwatch.reset();
  }

  /// Add a new recorded clip to the list.
  ///
  /// Returns the created clip with unique ID.
  RecordingClip addClip({
    required EditorVideo video,
    required model.AspectRatio aspectRatio,
    Duration? duration,
    String? thumbnailPath,
  }) {
    final clip = RecordingClip(
      id: 'clip_${DateTime.now().millisecondsSinceEpoch}_${_clipCounter++}',
      video: video,
      duration:
          duration ??
          Duration(microseconds: _recordStopwatch.elapsedMicroseconds),
      recordedAt: .now(),
      thumbnailPath: thumbnailPath,
      aspectRatio: aspectRatio,
    );

    _clips.add(clip);
    Log.info(
      '📎 Added clip: ${clip.id}, duration: ${clip.durationInSeconds}s',
      name: 'ClipManagerNotifier',
      category: .video,
    );

    if (duration == null) {
      resetRecording();
    }
    state = state.copyWith(
      clips: List.unmodifiable(_clips),
      activeRecordingDuration: .zero,
    );

    return clip;
  }

  /// Add multiple clips at once (e.g., from draft restoration).
  ///
  /// Appends all clips to the end of the current clip list and updates state.
  /// Used when restoring drafts or importing multiple clips from library.
  void addMultipleClips(List<RecordingClip> clips) {
    if (clips.isEmpty) {
      Log.debug(
        '📎 No clips to add - empty list provided',
        name: 'ClipManagerNotifier',
        category: .video,
      );
      return;
    }

    final previousCount = _clips.length;
    _clips.addAll(clips);

    Log.info(
      '📎 Added ${clips.length} clips (${previousCount} → ${_clips.length} total)',
      name: 'ClipManagerNotifier',
      category: .video,
    );

    state = state.copyWith(clips: List.unmodifiable(_clips));
  }

  /// Delete a clip by ID.
  void deleteClip(String clipId) {
    final index = _clips.indexWhere((c) => c.id == clipId);
    if (index == -1) {
      Log.warning(
        '⚠️ Cannot delete - clip not found: $clipId',
        name: 'ClipManagerNotifier',
        category: .video,
      );
      return;
    }

    _clips.removeAt(index);
    Log.info(
      '🗑️  Deleted clip: $clipId (${_clips.length} remaining)',
      name: 'ClipManagerNotifier',
      category: .video,
    );
    state = state.copyWith(clips: List.unmodifiable(_clips));
  }

  /// Reorder a single clip from oldIndex to newIndex.
  ///
  /// Moves the clip at [oldIndex] to [newIndex], shifting other clips
  /// accordingly.
  void reorderClip(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= _clips.length ||
        newIndex < 0 ||
        newIndex >= _clips.length) {
      Log.warning(
        '⚠️ Invalid reorder indices: $oldIndex → $newIndex (length: ${_clips.length})',
        name: 'ClipManagerNotifier',
        category: .video,
      );
      return;
    }

    if (oldIndex == newIndex) return;

    final clip = _clips.removeAt(oldIndex);
    _clips.insert(newIndex, clip);

    Log.info(
      '📎 Reordered clip ${clip.id}: $oldIndex → $newIndex',
      name: 'ClipManagerNotifier',
      category: .video,
    );

    state = state.copyWith(clips: List.unmodifiable(_clips));
  }

  /// Update thumbnail path for a clip.
  void updateThumbnail(String clipId, String thumbnailPath) {
    final index = _clips.indexWhere((c) => c.id == clipId);
    if (index != -1) {
      _clips[index] = _clips[index].copyWith(thumbnailPath: thumbnailPath);
      state = state.copyWith(clips: List.unmodifiable(_clips));
      Log.debug(
        '🖼️  Updated thumbnail for clip: $clipId',
        name: 'ClipManagerNotifier',
        category: .video,
      );
    } else {
      Log.warning(
        '⚠️ Cannot update thumbnail - clip not found: $clipId',
        name: 'ClipManagerNotifier',
        category: .video,
      );
    }
  }

  /// Update duration for a clip (from metadata extraction).
  void updateClipDuration(String clipId, Duration duration) {
    final index = _clips.indexWhere((c) => c.id == clipId);
    if (index != -1) {
      _clips[index] = _clips[index].copyWith(duration: duration);
      state = state.copyWith(clips: List.unmodifiable(_clips));
      Log.debug(
        '⏱️  Updated duration for clip: $clipId → ${duration.inMilliseconds}ms',
        name: 'ClipManagerNotifier',
        category: .video,
      );
    } else {
      Log.warning(
        '⚠️ Cannot update duration - clip not found: $clipId',
        name: 'ClipManagerNotifier',
        category: .video,
      );
    }
  }

  /// Select a clip for editing.
  void selectClip(String? clipId) {
    state = state.copyWith(selectedClipId: clipId);
  }

  /// Remove the most recent clip (undo last recording).
  void removeLastClip() {
    if (_clips.isEmpty) {
      Log.debug(
        'Cannot remove last clip - no clips available',
        name: 'ClipManagerNotifier',
        category: .video,
      );
      return;
    }
    final lastClip = _clips.last;
    deleteClip(lastClip.id);
  }

  /// Remove all clips and reset state.
  void clearAll() {
    _clips.clear();
    Log.info(
      '📎 Cleared all clips',
      name: 'ClipManagerNotifier',
      category: .video,
    );
    state = ClipManagerState();
  }

  /// Opens the clip library screen in selection mode.
  ///
  /// When a clip is selected, it is imported into the current editing session.
  Future<void> pickFromLibrary(BuildContext context) async {
    Log.info(
      '📹 Opening clip library in selection mode',
      name: 'VideoEditorMoreSheet',
      category: .video,
    );

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF101111),
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: .vertical(top: .circular(32)),
      ),
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const ClipLibraryScreen(selectionMode: true),
    );

    Log.info(
      '📹 Closed clip library',
      name: 'VideoEditorMoreSheet',
      category: .video,
    );
  }

  /// Save clip(s) to device library.
  Future<void> saveClipsToLibrary() async {
    Log.info(
      '💾 Starting to save ${_clips.length} clips to library',
      name: 'ClipManagerNotifier',
      category: .video,
    );

    try {
      final clipService = ref.read(clipLibraryServiceProvider);
      int savedCount = 0;

      for (final clip in _clips) {
        try {
          final savedClip = SavedClip(
            id: clip.id,
            aspectRatio: clip.aspectRatio.name,
            createdAt: DateTime.now(),
            duration: clip.duration,
            filePath: await clip.video.safeFilePath(),
            thumbnailPath: clip.thumbnailPath,
          );
          await clipService.saveClip(savedClip);
          savedCount++;

          Log.debug(
            '✅ Saved clip ${clip.id} to library (${clip.durationInSeconds}s)',
            name: 'ClipManagerNotifier',
            category: .video,
          );
        } catch (e, stackTrace) {
          Log.error(
            '❌ Failed to save clip ${clip.id}: $e',
            name: 'ClipManagerNotifier',
            category: .video,
            error: e,
            stackTrace: stackTrace,
          );
          // Continue saving other clips even if one fails
        }
      }

      Log.info(
        '💾 Successfully saved $savedCount/${_clips.length} clips to library',
        name: 'ClipManagerNotifier',
        category: .video,
      );
    } catch (e, stackTrace) {
      Log.error(
        '❌ Failed to save clips to library: $e',
        name: 'ClipManagerNotifier',
        category: .video,
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Saves all clips to drafts.
  Future<void> saveToDrafts(BuildContext context) async {
    Log.info(
      '📹 Saving video to drafts',
      name: 'VideoEditorMoreSheet',
      category: .video,
    );

    try {
      final draft = VineDraft.create(
        clips: clips,
        title: '',
        description: '',
        hashtags: [],
        selectedApproach: 'video',
      );
      final prefs = await SharedPreferences.getInstance();
      final draftService = DraftStorageService(prefs);
      await draftService.saveDraft(draft);

      ref.read(videoEditorProvider.notifier).setDraftId(draft.id);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved to drafts'),
          backgroundColor: VineTheme.vineGreen,
        ),
      );
    } catch (e, stackTrace) {
      Log.error(
        '❌ Failed to save to drafts: $e',
        name: 'ClipManagerNotifier',
        category: LogCategory.video,
        error: e,
        stackTrace: stackTrace,
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to save to drafts'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
