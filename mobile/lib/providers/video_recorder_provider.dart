// ABOUTME: Riverpod state management for VineRecordingController
// ABOUTME: Provides reactive state updates for recording UI without ChangeNotifier

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:models/models.dart' as model show AspectRatio;
import 'package:openvine/models/video_recorder/video_recorder_flash_mode.dart';
import 'package:openvine/models/video_recorder/video_recorder_provider_state.dart';
import 'package:openvine/models/video_recorder/video_recorder_timer_duration.dart';
import 'package:openvine/providers/clip_manager_provider.dart';
import 'package:openvine/router/nav_extensions.dart';
import 'package:openvine/services/video_recorder/camera/camera_base_service.dart';
import 'package:openvine/services/video_recorder/camera/camera_permission_service.dart';
import 'package:openvine/services/video_thumbnail_service.dart';
import 'package:openvine/utils/unified_logger.dart';
import 'package:pro_video_editor/pro_video_editor.dart';

/// Notifier that wraps VideoRecorderNotifier and provides reactive updates
class VideoRecorderNotifier extends Notifier<VideoRecorderUIState> {
  /// Creates a video recorder notifier.
  ///
  /// [cameraService] is an optional camera service override for testing.
  VideoRecorderNotifier([CameraService? cameraService])
    : _cameraServiceOverride = cameraService;

  final CameraService? _cameraServiceOverride;
  late final CameraService _cameraService;
  Timer? _focusPointTimer;

  double _baseZoomLevel = 1;
  bool _isDestroyed = false;

  @override
  VideoRecorderUIState build() {
    _cameraService =
        _cameraServiceOverride ??
        CameraService.create(
          onUpdateState: ({forceCameraRebuild}) {
            // Don't update state if provider is being destroyed
            if (_isDestroyed || !ref.mounted) return;

            updateState(
              cameraRebuildCount: forceCameraRebuild ?? false
                  ? state.cameraRebuildCount + 1
                  : null,
            );
          },
        );

    // Setup cleanup when provider is disposed
    ref.onDispose(() async {
      if (!_isDestroyed) {
        _isDestroyed = true; // Set flag before cleanup
        _focusPointTimer?.cancel();
        try {
          await _cameraService.dispose();
        } catch (e) {
          // Ignore camera disposal errors during cleanup
          Log.warning(
            '🧹 Camera service disposal failed during cleanup: $e',
            name: 'VideoRecorderNotifier',
            category: .system,
          );
        }
      }
    });

    return const VideoRecorderUIState();
  }

  /// Initialize camera and request permissions.
  ///
  /// Returns `true` if successful, `false` if permissions denied.
  Future<bool> initialize({BuildContext? context}) async {
    _isDestroyed = false;

    // TODO(@hm21): cleanup all provider sessions

    // Check permissions using the dedicated service
    final hasPermissions = context != null && context.mounted
        ? await CameraPermissionService.ensurePermissionsWithDialog(context)
        : await CameraPermissionService.ensurePermissions();
    if (!hasPermissions) {
      return false;
    }

    await _cameraService.initialize();
    updateState(aspectRatio: .vertical);

    return true;
  }

  /// Handle app lifecycle changes (pause/resume).
  Future<void> handleAppLifecycleState(AppLifecycleState appState) async {
    await _cameraService.handleAppLifecycleState(appState);
  }

  /// Clean up resources and dispose camera service.
  Future<void> destroy() async {
    _isDestroyed = true;
    _focusPointTimer?.cancel();
    await _cameraService.dispose();

    // Auto-save as draft if recording completed but not published
    // Note: We can't await in dispose(), so we use unawaited future
    // The controller cleanup will be delayed until save completes via the
    // future chain
    /* TODO(@hm21): _autoSaveDraftBeforeDispose()
        .then((_) {
          // Clear callback to prevent memory leaks
          _controller.setStateChangeCallback(null);
          _controller.dispose();
        })
        .catchError((e) {
          Log.error(
            'Error during auto-save, proceeding with cleanup: $e',
            name: 'VineRecordingProvider',
            category: .system,
          );
          // Ensure cleanup happens even if save fails
          _controller.setStateChangeCallback(null);
          _controller.dispose();
        })
        .whenComplete(() {
          super.dispose();
        }); */
  }

  /// Toggle flash mode between `off`, `torch`, and `auto`.
  ///
  /// Returns `true` if flash mode was successfully changed, `false` otherwise.
  Future<bool> toggleFlash() async {
    final DivineFlashMode newMode = switch (state.flashMode) {
      .off => .torch,
      .torch => .auto,
      .auto => .off,
    };
    final success = await _cameraService.setFlashMode(newMode);
    if (!success) {
      return false;
    }
    state = state.copyWith(flashMode: newMode);
    return true;
  }

  /// Toggle between square (1:1) and vertical (9:16) aspect ratios.
  void toggleAspectRatio() {
    final model.AspectRatio newRatio = state.aspectRatio == .square
        ? .vertical
        : .square;

    setAspectRatio(newRatio);
  }

  /// Set aspect ratio for recording
  void setAspectRatio(model.AspectRatio ratio) {
    state = state.copyWith(aspectRatio: ratio);
  }

  /// Switch between front and back camera.
  Future<void> switchCamera() async {
    final success = await _cameraService.switchCamera();

    if (!success) {
      Log.warning(
        '⚠️ Camera switch failed - no available cameras to switch',
        name: 'VideoRecorderNotifier',
        category: .video,
      );
      return;
    }
    _baseZoomLevel = 1;

    Log.info(
      '🔄 Camera switched successfully - zoom reset to 1.0x',
      name: 'VideoRecorderNotifier',
      category: .video,
    );

    // Force state update to rebuild UI with new camera preview
    // Increment camera switch count to ensure state object changes and
    // triggers UI rebuild
    state = state.copyWith(zoomLevel: 1);
    updateState();
  }

  /// Set camera zoom level (within min/max bounds).
  Future<void> setZoomLevel(double value) async {
    if (value > _cameraService.maxZoomLevel ||
        value < _cameraService.minZoomLevel) {
      Log.debug(
        '⚠️ Zoom level $value out of bounds '
        '(${_cameraService.minZoomLevel}-${_cameraService.maxZoomLevel})',
        name: 'VideoRecorderNotifier',
        category: .video,
      );
      return;
    }

    final success = await _cameraService.setZoomLevel(value);
    if (!success) {
      Log.warning(
        '⚠️ Failed to set zoom level to $value',
        name: 'VideoRecorderNotifier',
        category: .video,
      );
      return;
    }
    state = state.copyWith(zoomLevel: value);
  }

  /// Set camera focus point (normalized 0.0-1.0 coordinates).
  Future<void> setFocusPoint(Offset value) async {
    final success = await _cameraService.setFocusPoint(value);
    if (!success) {
      Log.warning(
        '⚠️ Failed to set focus point at (${value.dx.toStringAsFixed(2)}, '
        '${value.dy.toStringAsFixed(2)})',
        name: 'VideoRecorderNotifier',
        category: .video,
      );
      return;
    }

    // Cancel previous timer if exists
    _focusPointTimer?.cancel();

    state = state.copyWith(focusPoint: value);

    // Hide focus point after 1.5 seconds
    _focusPointTimer = Timer(const Duration(milliseconds: 800), () {
      if (!_isDestroyed) {
        state = state.copyWith(focusPoint: .zero);
        _focusPointTimer = null;
      }
    });
  }

  /// Set camera exposure point (normalized 0.0-1.0 coordinates).
  Future<void> setExposurePoint(Offset value) async {
    final success = await _cameraService.setExposurePoint(value);
    if (!success) {
      Log.warning(
        '⚠️ Failed to set exposure point at (${value.dx.toStringAsFixed(2)}, '
        '${value.dy.toStringAsFixed(2)})',
        name: 'VideoRecorderNotifier',
        category: .video,
      );
    }
  }

  /// Toggle recording state (start if idle, stop if recording).
  Future<void> toggleRecording() async {
    switch (state.recordingState) {
      case .idle:
        await startRecording();
      case .error:
      case .recording:
        await stopRecording();
    }
  }

  /// Start video recording with optional timer countdown.
  Future<void> startRecording() async {
    _baseZoomLevel = state.zoomLevel;
    state = state.copyWith(recordingState: .recording);

    // Handle timer countdown
    if (state.timerDuration != .off) {
      final seconds = state.timerDuration.duration.inSeconds;
      Log.info(
        '⏱️  Starting ${seconds}s countdown before recording',
        name: 'VideoRecorderNotifier',
        category: .video,
      );

      for (var i = seconds; i > 0; i--) {
        if (_isDestroyed) return; // Stop countdown if disposed
        state = state.copyWith(countdownValue: i);
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      if (_isDestroyed) return; // Stop before starting recording if disposed
      state = state.copyWith(countdownValue: 0);
    }

    if (_isDestroyed) return; // Don't start recording if disposed
    Log.info(
      '🎥 Recording started - aspect ratio: ${state.aspectRatio.name}',
      name: 'VideoRecorderNotifier',
      category: .video,
    );
    await _cameraService.startRecording();
    ref.read(clipManagerProvider.notifier).startRecording();
  }

  /// Stop recording and process clip (metadata, thumbnail).
  Future<void> stopRecording() async {
    if (!state.isRecording) return;

    Log.info(
      '⏹️  Stopping recording and processing clip...',
      name: 'VideoRecorderNotifier',
      category: .video,
    );

    final clipProvider = ref.read(clipManagerProvider.notifier)
      ..stopRecording();
    final videoResult = await _cameraService.stopRecording();

    if (videoResult == null) {
      Log.warning(
        '⚠️ Recording stopped but no video file returned from camera service',
        name: 'VideoRecorderNotifier',
        category: .video,
      );
      state = state.copyWith(recordingState: .idle);
      return;
    }

    state = state.copyWith(recordingState: .idle);

    /// Add the recorded clip to ClipManager
    final clip = clipProvider.addClip(
      video: videoResult,
      aspectRatio: state.aspectRatio,
    );

    Log.info(
      '✅ Clip added successfully - ID: ${clip.id}',
      name: 'VideoRecorderNotifier',
      category: .video,
    );

    /// We used the stopwatch as a temporary timer to set an expected duration.
    /// However, we now read the exact video duration in the background and
    /// update it.
    // Extract video metadata and update duration
    final metadata = await ProVideoEditor.instance.getMetadata(videoResult);
    clipProvider.updateClipDuration(clip.id, metadata.duration);
    Log.debug(
      '📊 Video duration: ${metadata.duration.inMilliseconds}ms',
      name: 'VideoRecorderNotifier',
      category: .video,
    );

    // Generate and attach thumbnail
    final thumbnailPath = await VideoThumbnailService.extractThumbnail(
      videoPath: await videoResult.safeFilePath(),
    );
    if (thumbnailPath != null) {
      clipProvider.updateThumbnail(clip.id, thumbnailPath);
      Log.debug(
        '🖼️  Thumbnail generated: $thumbnailPath',
        name: 'VideoRecorderNotifier',
        category: .video,
      );
    } else {
      Log.warning(
        '⚠️ Thumbnail generation failed',
        name: 'VideoRecorderNotifier',
        category: .video,
      );
    }
  }

  /// Adjust zoom by vertical drag distance during long press.
  Future<void> zoomByLongPressMove(Offset offsetFromOrigin) async {
    // At 240px drag distance, reach maxZoomLevel
    const maxDragDistance = 240.0;
    // Calculate upward drag distance (negative Y = upward)
    final dragDistance = (-offsetFromOrigin.dy).clamp(0.0, maxDragDistance);

    final availableZoomRange = _cameraService.maxZoomLevel - _baseZoomLevel;
    final zoomLevel =
        _baseZoomLevel + (dragDistance / maxDragDistance) * availableZoomRange;

    await setZoomLevel(zoomLevel);
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _baseZoomLevel = state.zoomLevel;
  }

  Future<void> _handleScaleUpdate(ScaleUpdateDetails details) async {
    // Linear zoom: map scale gesture to zoom range
    // scale < 1.0 = zoom out, scale > 1.0 = zoom in
    final scaleChange = details.scale - 1.0; // -1.0 to +2.0 range
    final normalizedChange = scaleChange.clamp(-1.0, 2.0);

    // Calculate zoom based on available range from base level
    final zoomRangeDown = _baseZoomLevel - _cameraService.minZoomLevel;
    final zoomRangeUp = _cameraService.maxZoomLevel - _baseZoomLevel;

    final newZoom = normalizedChange >= 0
        ? _baseZoomLevel + (normalizedChange / 2.0) * zoomRangeUp
        : _baseZoomLevel + normalizedChange * zoomRangeDown;

    final clampedZoom = newZoom.clamp(
      _cameraService.minZoomLevel,
      _cameraService.maxZoomLevel,
    );

    // Only update if change is significant to avoid excessive updates
    if ((state.zoomLevel - clampedZoom).abs() > 0.01) {
      await setZoomLevel(clampedZoom);
    }
  }

  Future<void> _handleTapDown(
    TapDownDetails details,
    BoxConstraints constraints,
  ) async {
    final offset = Offset(
      details.localPosition.dx / constraints.maxWidth,
      details.localPosition.dy / constraints.maxHeight,
    );
    await Future.wait([setFocusPoint(offset), setExposurePoint(offset)]);
  }

  /// Get the camera preview widget from the controller
  Widget? get previewWidget => _cameraService.isInitialized
      ? _cameraService.buildPreviewWidget(
          onTapDown: _handleTapDown,
          onScaleStart: _handleScaleStart,
          onScaleUpdate: _handleScaleUpdate,
        )
      : null;

  /// Close video recorder and navigate away.
  void closeVideoRecorder(BuildContext context) {
    Log.info(
      '📹 X CANCEL - navigating away from camera',
      name: 'VideoRecorderNotifier',
      category: .video,
    );
    // Try to pop if possible, otherwise go home.
    if (context.canPop()) {
      context.pop();
    } else {
      // No screen to pop to (navigated via go), go home instead.
      context.goHome();
    }
  }

  /// Navigate to video editor screen, pausing camera during transition.
  ///
  /// Pauses camera lifecycle, navigates to editor, and resumes camera on
  /// return.
  Future<void> openVideoEditor(BuildContext context) async {
    await handleAppLifecycleState(.paused);
    if (!context.mounted) return;

    await context.pushVideoEditor();
    if (!context.mounted) return;

    await handleAppLifecycleState(.resumed);
  }

  /// Update the state based on the current camera state.
  void updateState({int? cameraRebuildCount, model.AspectRatio? aspectRatio}) {
    // Check if ref is still mounted before updating state
    if (!ref.mounted) return;

    state = VideoRecorderUIState(
      cameraRebuildCount: cameraRebuildCount ?? state.cameraRebuildCount,
      countdownValue: 0,
      zoomLevel: 1,
      focusPoint: .zero,
      aspectRatio: aspectRatio ?? state.aspectRatio,
      flashMode: .off,
      timerDuration: .off,
      recordingState: .idle,
      cameraSensorAspectRatio: _cameraService.cameraAspectRatio,
      canRecord: _cameraService.canRecord,
      isCameraInitialized: _cameraService.isInitialized,
      hasFlash: _cameraService.hasFlash,
      canSwitchCamera: _cameraService.canSwitchCamera,
    );
  }

  /// Cycle timer duration
  void cycleTimer() {
    final TimerDuration newTimer = switch (state.timerDuration) {
      .off => .three,
      .three => .ten,
      .ten => .off,
    };
    state = state.copyWith(timerDuration: newTimer);
  }

  void reset() {
    state = VideoRecorderUIState();
  }

  /// TODO(@hm21): DELETE Deprecated code Below ----------------------
  /*  VineRecordingController _controller = VineRecordingController();

  // Track whether video was successfully published to prevent auto-save
  bool _wasPublished = false;

  // Track the draft ID we created in stopRecording to prevent duplicate drafts
  String? _currentDraftId;

  // UI control methods

  Future<void> oldStopRecording() async {
    if (!state.isRecording) return;

    await _cameraService.stopRecording();

    state = state.copyWith(recordingState: .idle);
    updateState();

    final result = await _controller.finishRecording();
    updateState();
    Log.info(
      '🔍 PROOFMODE DEBUG: stopRecording() called',
      name: 'VideoRecorderNotifier',
      category: .video,
    );
    Log.info(
      '🔍 Video file: ${result.$1?.path ?? "NULL"}',
      name: 'VideoRecorderNotifier',
      category: .video,
    );
    Log.info(
      '🔍 Native proof: ${result.$2?.toString() ?? "NULL"}',
      name: 'VideoRecorderNotifier',
      category: .video,
    );
    // Auto-create draft immediately after recording finishes
    if (result.$1 != null) {
      try {
        final draftStorage = await _ref.read(
          draftStorageServiceProvider.future,
        );

        // Serialize NativeProofData to JSON if available
        String? proofManifestJson;
        if (result.$2 != null) {
          try {
            proofManifestJson = jsonEncode(result.$2!.toJson());
            Log.info(
              '📜 Native ProofMode data attached to draft',
              name: 'VideoRecorderNotifier',
              category: .video,
            );
            Log.info(
              '🔍 Proof JSON length: ${proofManifestJson.length} chars',
              name: 'VideoRecorderNotifier',
              category: .video,
            );
            Log.info(
              '🔍 Proof verification level: ${result.$2!.verificationLevel}',
              name: 'VideoRecorderNotifier',
              category: .video,
            );
          } catch (e) {
            Log.error(
              'Failed to serialize NativeProofData for draft: $e',
              name: 'VideoRecorderNotifier',
              category: .video,
            );
          }
        } else {
          Log.warning(
            '⚠️ NO NATIVE PROOF DATA FROM RECORDING! ProofMode will not be 
            published.',
            name: 'VideoRecorderNotifier',
            category: .video,
          );
        }

        final draft = VineDraft.create(
          videoFile: result.$1!,
          title: 'Do it for the Vine!',
          description: '',
          hashtags: ['openvine', 'vine'],
          frameCount: _controller.segments.length,
          selectedApproach: 'native',
          proofManifestJson: proofManifestJson,
          aspectRatio: _controller.aspectRatio,
        );

        await draftStorage.saveDraft(draft);
        _currentDraftId =
            draft.id; // Track draft to prevent duplicate on dispose
        Log.info(
          '📹 Auto-created draft: ${draft.id}',
          name: 'VideoRecorderNotifier',
          category: .video,
        );

        return RecordingResult(
          videoFile: result.$1,
          draftId: draft.id,
          nativeProof: result.$2,
        );
      } catch (e) {
        Log.error(
          '📹 Failed to auto-create draft: $e',
          name: 'VideoRecorderNotifier',
          category: .video,
        );
        // Still return the video file so user can manually save
        return RecordingResult(
          videoFile: result.$1,
          draftId: null,
          nativeProof: result.$2,
        );
      }
    }

    return RecordingResult(
      videoFile: null,
      draftId: null,
      nativeProof: result.$2,
    );
  }

  /// Stop the current segment without finishing the recording.
  /// This allows the user to record multiple segments before finalizing.
  Future<void> stopSegment() async {
    await _controller.stopRecording();
    updateState();
    Log.info(
      '📹 Segment stopped, total segments: ${_controller.segments.length}',
      name: 'VideoRecorderNotifier',
      category: .video,
    );
  }

  Future<(File?, NativeProofData?)> finishRecording() async {
    final result = await _controller.finishRecording();
    updateState();
    return result;
  }

  /// Extract individual segment files without concatenating
  /// Returns a list of ExtractedSegment with metadata for each segment
  Future<List<ExtractedSegment>> extractSegmentFiles() async {
    final result = await _controller.extractSegmentFiles();
    updateState();
    return result;
  }

  /// Set the duration of previously recorded clips from ClipManager
  /// Call this when returning to camera to record additional segments
  void setPreviouslyRecordedDuration(Duration duration) {
    _controller.setPreviouslyRecordedDuration(duration);
    updateState();
  }

  /// Clear segments after they've been added to ClipManager
  /// This prevents duplicate processing when user navigates back
  void clearSegments() {
    _controller.clearSegments();
    updateState();
  }

  void reset() {
    _controller.reset();
    _wasPublished = false; // Reset publish flag for new recording
    _currentDraftId = null; // Clear draft ID for new recording
    updateState();
  }

  /// Mark recording as published to prevent auto-save on dispose
  void markAsPublished() {
    _wasPublished = true;
    Log.info(
      'Recording marked as published - auto-save will be skipped',
      name: 'VideoRecordingProvider',
      category: .system,
    );
  }

  /// Clean up temp files and reset for new recording
  Future<void> cleanupAndReset() async {
    try {
      // Clean up temp files first
      _controller.cleanupFiles();
      // Then reset state
      _controller.reset();
      _wasPublished = false;
      _currentDraftId = null; // Clear draft ID for new recording
      updateState();
      Log.info(
        'Cleaned up temp files and reset for new recording',
        name: 'VideoRecordingProvider',
        category: .system,
      );
    } catch (e) {
      Log.error(
        'Error during cleanup and reset: $e',
        name: 'VideoRecordingProvider',
        category: .system,
      );
    }
  }

  /// Release camera resources to free memory when navigating away.
  ///
  /// Call this when moving to the video editor to release CameraX resources.
  /// The camera can be re-initialized by calling initialize() again.
  void releaseCamera() {
    _controller.releaseCamera();
    updateState();
  }

  /// Auto-save recording as draft if completed but not published
  Future<void> _autoSaveDraftBeforeDispose() async {
      try {
      // Skip auto-save if video was successfully published
      if (_wasPublished) {
        Log.info(
          'Skipping auto-save - video was published',
          name: 'VideoRecordingProvider',
          category: .system,
        );
        return;
      }

      // Skip auto-save if we already created a draft in stopRecording()
      if (_currentDraftId != null) {
        Log.info(
          'Skipping auto-save - draft already created: $_currentDraftId',
          name: 'VideoRecordingProvider',
          category: .system,
        );
        return;
      }

      // Only auto-save if recording is completed
      if (_controller.state != VideoRecordingState.completed) {
        return;
      }

      // Check if we have segments to save
      if (_controller.segments.isEmpty) {
        Log.debug(
          'No segments to auto-save as draft',
          name: 'VideoRecordingProvider',
          category: .system,
        );
        return;
      }

      // Get the video file path from macOS single recording mode
      if (Platform.isMacOS &&
          _controller.cameraInterface is MacOSCameraInterface) {
        final macOSInterface =
            _controller.cameraInterface as MacOSCameraInterface;
        final videoPath = macOSInterface.currentRecordingPath;

        if (videoPath != null && File(videoPath).existsSync()) {
          await _saveDraftFromPath(videoPath);
          return;
        }
      }

      // For other platforms or if macOS path not available, check segments
      final segment = _controller.segments.firstOrNull;
      if (segment?.filePath != null && File(segment!.filePath!).existsSync()) {
        await _saveDraftFromPath(segment.filePath!);
      }
    } catch (e) {
      Log.error(
        'Failed to auto-save draft on dispose: $e',
        name: 'VideoRecordingProvider',
        category: .system,
      );
      // Don't rethrow - ensure cleanup continues
    } 
  }

  /// Save draft from video file path
  Future<void> _saveDraftFromPath(String videoPath) async {
    try {
      final draftStorage = await _ref.read(draftStorageServiceProvider.future);

      // Copy video file to permanent draft location using app support directory (sandboxed)
      final appDir = await getApplicationSupportDirectory();
      final draftsDir = Directory(path.join(appDir.path, 'drafts'));
      if (!draftsDir.existsSync()) {
        draftsDir.createSync(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = path.extension(videoPath);
      final permanentPath = path.join(
        draftsDir.path,
        'draft_$timestamp$extension',
      );

      // Copy the file to permanent location
      final sourceFile = File(videoPath);
      final permanentFile = await sourceFile.copy(permanentPath);

      Log.info(
        '📁 Copied draft video to permanent location: $permanentPath',
        name: 'VideoRecordingProvider',
        category: .system,
      );

      // Create draft with permanent file path
      final draft = VineDraft.create(
        videoFile: permanentFile,
        title:
            'Untitled Draft - 
            ${DateTime.now().toLocal().toString().split('.')[0]}',
        description: '',
        hashtags: [],
        frameCount: 0,
        selectedApproach: 'auto',
        aspectRatio: _controller.aspectRatio,
      );

      await draftStorage.saveDraft(draft);

      Log.info(
        '✅ Auto-saved recording as draft: ${draft.id}',
        name: 'VideoRecordingProvider',
        category: .system,
      );
    } catch (e) {
      Log.error(
        'Failed to save draft: $e',
        name: 'VideoRecordingProvider',
        category: .system,
      );
      rethrow;
    }
  }

  // Getters that delegate to controller
  VineRecordingController get controller => _controller; */
}

/// Provider for video recorder state and operations.
final videoRecorderProvider =
    NotifierProvider<VideoRecorderNotifier, VideoRecorderUIState>(
      VideoRecorderNotifier.new,
    );
