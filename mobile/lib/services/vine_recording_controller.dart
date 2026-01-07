// ABOUTME: Universal Vine-style recording controller for all platforms
// ABOUTME: Handles press-to-record, release-to-pause segmented recording with cross-platform camera abstraction

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
// camera_macos removed - using NativeMacOSCamera for both preview and recording

import 'package:models/models.dart' as model show AspectRatio;
import 'package:openvine/models/video_recorder/video_recorder_flash_mode.dart';
import 'package:openvine/utils/async_utils.dart';

// TODO(@hm21): Delete all of it

/// Represents a single recording segment in the Vine-style recording
/// REFACTORED: Removed ChangeNotifier - now uses pure state management via Riverpod
class RecordingSegment {
  RecordingSegment({
    required this.startTime,
    required this.endTime,
    required this.duration,
    this.filePath,
  });
  final DateTime startTime;
  final DateTime endTime;
  final Duration duration;
  final String? filePath;

  double get durationInSeconds => duration.inMilliseconds / 1000.0;

  @override
  String toString() => 'Segment(${duration.inMilliseconds}ms)';
}

/// Result of extracting a segment file, with metadata for deferred processing
class ExtractedSegment {
  ExtractedSegment({
    required this.file,
    required this.duration,
    this.needsCrop = false,
    this.aspectRatio,
  });

  final File file;
  final Duration duration;

  /// Whether this segment needs cropping applied at export time
  /// True on Android where we defer encoding for performance
  final bool needsCrop;

  /// Target aspect ratio for cropping (if needsCrop is true)
  final model.AspectRatio? aspectRatio;
}

/// Platform-agnostic interface for camera operations
abstract class CameraPlatformInterface {
  Future<void> initialize();
  Future<void> startRecordingSegment(String filePath);
  Future<String?> stopRecordingSegment();
  Future<void> switchCamera();
  Future<void> setFlashMode(DivineFlashMode mode);
  Widget get previewWidget;
  bool get canSwitchCamera;
  void dispose();
}

/// macOS camera implementation using native platform channels
/// Uses single AVCaptureSession for both preview and recording via NativeMacOSCamera
class MacOSCameraInterface extends CameraPlatformInterface
    with AsyncInitialization {
  @override
  bool get canSwitchCamera => throw UnimplementedError();

  @override
  void dispose() {}

  @override
  Future<void> initialize() {
    throw UnimplementedError();
  }

  @override
  Widget get previewWidget => throw UnimplementedError();

  @override
  Future<void> setFlashMode(DivineFlashMode mode) {
    throw UnimplementedError();
  }

  @override
  Future<void> startRecordingSegment(String filePath) {
    throw UnimplementedError();
  }

  @override
  Future<String?> stopRecordingSegment() {
    throw UnimplementedError();
  }

  @override
  Future<void> switchCamera() {
    throw UnimplementedError();
  }

  /*  Widget? _previewWidget;
  String? currentRecordingPath;
  bool isRecording = false;
  int _currentCameraIndex = 0;
  int _availableCameraCount = 1;

  // For macOS single recording mode
  bool isSingleRecordingMode = false;
  final List<RecordingSegment> _virtualSegments = [];

  // Recording completion tracking
  DateTime? _recordingStartTime;
  DateTime? _currentSegmentStartTime;
  Timer? _maxDurationTimer;

  @override
  Future<void> initialize() async {
    startInitialization();

    // Get available cameras
    final cameras = await NativeMacOSCamera.getAvailableCameras();
    _availableCameraCount = cameras.length;
    Log.info(
      'Found $_availableCameraCount cameras on macOS',
      name: 'VineRecordingController',
      category: LogCategory.system,
    );

    // Initialize the native macOS camera for recording
    final nativeResult = await NativeMacOSCamera.initialize();
    if (!nativeResult) {
      throw Exception('Failed to initialize native macOS camera');
    }

    // Start native preview
    await NativeMacOSCamera.startPreview();

    // Create the camera widget using native frame stream (single AVCaptureSession)
    _previewWidget = CameraMacOSView(
      videoFormat: .mp4,
      // optional camera parameter, defaults to the Mac primary camera
      // deviceId: deviceId,
      // optional microphone parameter, defaults to the Mac primary microphone
      // audioDeviceId: audioDeviceId,
      cameraMode: CameraMacOSMode.video,
      onCameraInizialized: (CameraMacOSController controller) {
        // Complete initialization now that native camera is ready for recording
        completeInitialization();
      },
    );

    Log.info(
      '📱 Native macOS camera initialized successfully',
      name: 'VineRecordingController',
      category: LogCategory.system,
    );
  }

  @override
  Future<void> startRecordingSegment(String filePath) async {
    Log.info(
      '📱 Starting recording segment, initialized: $isInitialized, recording: $isRecording, singleMode: $isSingleRecordingMode',
      name: 'VineRecordingController',
      category: LogCategory.system,
    );

    // Wait for visual preview to be initialized
    try {
      await waitForInitialization(timeout: const Duration(seconds: 5));
    } catch (e) {
      Log.error(
        'macOS camera failed to initialize: $e',
        name: 'VineRecordingController',
        category: LogCategory.system,
      );
      throw Exception(
        'macOS camera not initialized after waiting 5 seconds: $e',
      );
    }

    // For macOS, use single recording mode - one continuous native recording
    // with virtual segments tracked in software
    if (!isSingleRecordingMode && !isRecording) {
      // First segment - start the native recording
      // Don't set currentRecordingPath yet - native will provide the actual path
      isRecording = true;
      isSingleRecordingMode = true;
      _recordingStartTime = DateTime.now();
      _currentSegmentStartTime = _recordingStartTime;

      // Start native recording
      final started = await NativeMacOSCamera.startRecording();
      if (!started) {
        isRecording = false;
        isSingleRecordingMode = false;
        _recordingStartTime = null;
        _currentSegmentStartTime = null;
        throw Exception('Failed to start native macOS recording');
      }

      Log.info(
        'Started native macOS single recording mode (segment 1)',
        name: 'VineRecordingController',
        category: LogCategory.system,
      );
    } else if (isSingleRecordingMode && isRecording) {
      // Subsequent segments - native recording continues, just track segment start
      _currentSegmentStartTime = DateTime.now();
      Log.info(
        'Native macOS recording continues - starting segment ${_virtualSegments.length + 2}',
        name: 'VineRecordingController',
        category: LogCategory.system,
      );
    }
    // Note: The case (isSingleRecordingMode && !isRecording) should not happen
    // since we keep isRecording=true between segments
  }

  @override
  Future<String?> stopRecordingSegment() async {
    Log.debug(
      '📱 Pausing segment, recording: $isRecording, singleMode: $isSingleRecordingMode',
      name: 'VineRecordingController',
      category: LogCategory.system,
    );

    if (!isSingleRecordingMode || !isRecording) {
      return null;
    }

    // In single recording mode, track the segment end but KEEP native recording going
    // This allows multiple segments to be recorded continuously
    if (_currentSegmentStartTime != null) {
      final endTime = DateTime.now();
      final duration = endTime.difference(_currentSegmentStartTime!);

      final segment = RecordingSegment(
        startTime: _currentSegmentStartTime!,
        endTime: endTime,
        duration: duration,
        filePath:
            '', // Placeholder - actual path comes from completeRecording()
      );

      _virtualSegments.add(segment);
      Log.info(
        'Tracked virtual segment ${_virtualSegments.length}: ${duration.inMilliseconds}ms (native recording continues)',
        name: 'VineRecordingController',
        category: LogCategory.system,
      );
    }

    // Clear segment start time (will be set again on next segment start)
    _currentSegmentStartTime = null;

    // Return null - file path only comes from completeRecording() at the end
    return null;
  }

  /// Complete the recording and get the final file
  Future<String?> completeRecording() async {
    if (!isRecording) {
      return null;
    }

    _maxDurationTimer?.cancel();

    // If there's an active segment in progress, track it before stopping
    if (_currentSegmentStartTime != null) {
      final endTime = DateTime.now();
      final duration = endTime.difference(_currentSegmentStartTime!);

      final segment = RecordingSegment(
        startTime: _currentSegmentStartTime!,
        endTime: endTime,
        duration: duration,
        filePath: '', // Will be updated below
      );

      _virtualSegments.add(segment);
      Log.info(
        'Tracked final segment ${_virtualSegments.length}: ${duration.inMilliseconds}ms',
        name: 'VineRecordingController',
        category: LogCategory.system,
      );
    }

    isRecording = false;

    // Stop native recording and get the file path
    final recordedPath = await NativeMacOSCamera.stopRecording();

    if (recordedPath != null && recordedPath.isNotEmpty) {
      // The native implementation returns the actual file path
      currentRecordingPath = recordedPath;

      // Calculate total duration from all segments
      final totalDuration = _virtualSegments.fold<Duration>(
        Duration.zero,
        (sum, segment) => sum + segment.duration,
      );

      Log.info(
        'Native macOS recording completed: $recordedPath (${_virtualSegments.length} segments, total: ${totalDuration.inMilliseconds}ms)',
        name: 'VineRecordingController',
        category: LogCategory.system,
      );

      // Don't clear isSingleRecordingMode or _recordingStartTime here - they're needed by extractSegmentFiles()
      // They will be cleared in reset() or when starting a new recording
      _currentSegmentStartTime = null;

      return recordedPath;
    } else {
      Log.error(
        'Native macOS recording failed - no file path returned',
        name: 'VineRecordingController',
        category: LogCategory.system,
      );
      // Clear flags on error
      isSingleRecordingMode = false;
      _recordingStartTime = null;
      _currentSegmentStartTime = null;
      return null;
    }
  }

  /// Stop the single recording mode and return the final file
  Future<String?> stopSingleRecording() async {
    Log.debug(
      '📱 Stopping native macOS single recording mode',
      name: 'VineRecordingController',
      category: LogCategory.system,
    );

    if (!isSingleRecordingMode || !isRecording) {
      return null;
    }

    return await completeRecording();
  }

  /// Wait for recording completion using proper async pattern
  Future<String> waitForRecordingCompletion({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    // For native implementation, we complete the recording directly
    final path = await completeRecording();
    if (path != null) {
      return path;
    }
    throw TimeoutException('Recording completion failed');
  }

  /// Get virtual segments for macOS single recording mode
  List<RecordingSegment> getVirtualSegments() => _virtualSegments;

  /// Get the timestamp when native recording started (for calculating video offsets)
  DateTime? get recordingStartTime => _recordingStartTime;

  @override
  Widget get previewWidget {
    // Return the native frame preview widget, or placeholder if not ready
    if (_previewWidget == null) {
      if (isInitialized) {
        Log.info(
          '📱 macOS camera initialized but preview widget not created yet',
          name: 'VineRecordingController',
          category: LogCategory.system,
        );
      }
      // Return placeholder until preview widget is ready
      return const CameraPreviewPlaceholder();
    }
    return _previewWidget!;
  }

  @override
  bool get canSwitchCamera => _availableCameraCount > 1;

  @override
  Future<void> switchCamera() async {
    try {
      if (_availableCameraCount <= 1) {
        Log.info(
          'Only one camera available on macOS, cannot switch',
          name: 'VineRecordingController',
          category: LogCategory.system,
        );
        return;
      }

      // Cycle to next camera
      final nextCameraIndex = (_currentCameraIndex + 1) % _availableCameraCount;

      Log.info(
        'Switching macOS camera from $_currentCameraIndex to $nextCameraIndex',
        name: 'VineRecordingController',
        category: LogCategory.system,
      );

      /*   final success = await NativeMacOSCamera.switchCamera(nextCameraIndex);

      if (success) {
        _currentCameraIndex = nextCameraIndex;
        Log.info(
          '📱 macOS camera switched successfully to camera $_currentCameraIndex',
          name: 'VineRecordingController',
          category: LogCategory.system,
        );
      } else {
        Log.error(
          'Failed to switch macOS camera to index $nextCameraIndex',
          name: 'VineRecordingController',
          category: LogCategory.system,
        );
      } */
    } catch (e) {
      Log.error(
        'macOS camera switching failed: $e',
        name: 'VineRecordingController',
        category: LogCategory.system,
      );
    }
  }

  @override
  Future<void> setFlashMode(FlashMode mode) async {
    Log.debug(
      'Flash mode not supported on macOS cameras',
      name: 'VineRecordingController',
      category: LogCategory.system,
    );
    // macOS cameras typically don't have flash/torch functionality
    // This is a no-op to maintain interface compatibility
  }

  @override
  void dispose() {
    _maxDurationTimer?.cancel();
    // Stop any active recording
    if (isRecording) {
      NativeMacOSCamera.stopRecording();
      isRecording = false;
    }
    // Stop preview and dispose native camera resources
    NativeMacOSCamera.stopPreview();
    NativeMacOSCamera.dispose();
  }

  /// Reset the interface state (for reuse)
  void reset() {
    _maxDurationTimer?.cancel();
    isRecording = false;
    isSingleRecordingMode = false;
    currentRecordingPath = null;
    _virtualSegments.clear();
    _recordingStartTime = null;
    _currentSegmentStartTime = null;
    Log.debug(
      '📱 Native macOS camera interface reset',
      name: 'VineRecordingController',
      category: LogCategory.system,
    );
  }
}

/// Universal Vine recording controller that works across all platforms
/// REFACTORED: Removed ChangeNotifier - now uses pure state management via Riverpod
class VineRecordingController {
  static const Duration maxRecordingDuration = Duration(
    milliseconds: 6300,
  ); // 6.3 seconds like original Vine
  static const Duration minSegmentDuration = Duration(
    milliseconds: 33,
  ); // 1 frame at 30fps for stop-motion

  CameraPlatformInterface? _cameraInterface;
  VideoRecorderState _state = VideoRecorderState.idle;
  bool _cameraInitialized = false;

  /// Constructor
  VineRecordingController();

  // Getter for camera interface (needed for enhanced controls)
  CameraPlatformInterface? get cameraInterface => _cameraInterface;

  // Getter for camera preview widget
  Widget get previewWidget =>
      _cameraInterface?.previewWidget ?? SizedBox.shrink();

  // Callback for notifying UI of state changes during recording
  VoidCallback? _onStateChanged;

  // Recording session data
  final List<RecordingSegment> _segments = [];
  model.AspectRatio _aspectRatio =
      model.AspectRatio.vertical; // Default to 9:16 vertical
  DateTime? _currentSegmentStartTime;
  Timer? _progressTimer;
  Timer? _maxDurationTimer;
  String? _tempDirectory;

  // Progress tracking
  Duration _totalRecordedDuration = Duration.zero;
  Duration _previouslyRecordedDuration =
      Duration.zero; // From ClipManager clips
  bool _disposed = false;

  // Getters
  VideoRecorderState get state => _state;
  bool get isCameraInitialized => _cameraInitialized;
  List<RecordingSegment> get segments => List.unmodifiable(_segments);

  /// Get current aspect ratio
  model.AspectRatio get aspectRatio => _aspectRatio;

  /// Total recorded duration including both current session and previously recorded clips
  Duration get totalRecordedDuration =>
      _totalRecordedDuration + _previouslyRecordedDuration;

  /// Remaining time available for recording (accounts for previously recorded clips)
  Duration get remainingDuration =>
      maxRecordingDuration - totalRecordedDuration;

  /// Progress from 0.0 to 1.0 (accounts for previously recorded clips)
  double get progress =>
      totalRecordedDuration.inMilliseconds /
      maxRecordingDuration.inMilliseconds;

  /// Set the duration of previously recorded clips from ClipManager
  /// This affects progress bar and remaining time calculations
  /// Also resets current session duration to zero to avoid double-counting
  void setPreviouslyRecordedDuration(Duration duration) {
    _previouslyRecordedDuration = duration;
    // Reset current session duration to avoid double-counting when returning to record more
    _totalRecordedDuration = Duration.zero;
    _segments.clear();
    Log.info(
      '📹 Set previously recorded duration: ${duration.inMilliseconds}ms, reset current session',
      category: LogCategory.video,
    );
    _onStateChanged?.call();
  }

  /// Clear segments after they've been added to ClipManager
  /// This prevents duplicate processing when user navigates back
  void clearSegments() {
    _segments.clear();
    _totalRecordedDuration = Duration.zero;
    Log.info(
      '📹 Segments cleared (moved to ClipManager)',
      category: LogCategory.video,
    );
    _onStateChanged?.call();
  }

  bool get canRecord {
    return _cameraInitialized && remainingDuration > minSegmentDuration;
  }

  bool get hasSegments {
    if (_segments.isNotEmpty) return true;
    // For macOS, also check virtual segments since we use single-recording mode
    if (!kIsWeb &&
        Platform.isMacOS &&
        _cameraInterface is MacOSCameraInterface) {
      final macOSInterface = _cameraInterface as MacOSCameraInterface;
      return macOSInterface.getVirtualSegments().isNotEmpty;
    }
    return false;
  }

  /// Get the segment count including virtual segments for macOS
  int get segmentCount {
    if (_segments.isNotEmpty) return _segments.length;
    // For macOS, also check virtual segments since we use single-recording mode
    if (!kIsWeb &&
        Platform.isMacOS &&
        _cameraInterface is MacOSCameraInterface) {
      final macOSInterface = _cameraInterface as MacOSCameraInterface;
      return macOSInterface.getVirtualSegments().length;
    }
    return 0;
  }

  Widget get cameraPreview =>
      _cameraInterface?.previewWidget ??
      const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  Color(0xFF00B488),
                ), // Vine green
                strokeWidth: 3.0,
              ),
              SizedBox(height: 16),
              Text(
                'Divine',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Starting camera...',
                style: TextStyle(
                  color: Color(0xFFBBBBBB),
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      );

  bool get isRecording => _state == .recording;

  /// Check if camera switching is available on current platform
  bool get canSwitchCamera =>
      !isRecording && _cameraInterface?.canSwitchCamera == true;

  /// Set callback for state change notifications during recording
  void setStateChangeCallback(VoidCallback? callback) {
    _onStateChanged = callback;
  }

  /// Set aspect ratio (only allowed when not recording)
  void setAspectRatio(model.AspectRatio ratio) {
    if (state == VideoRecorderState.recording) {
      Log.warning(
        'Cannot change aspect ratio while recording',
        name: 'VineRecordingController',
        category: LogCategory.system,
      );
      return;
    }

    _aspectRatio = ratio;
    Log.info(
      'Aspect ratio changed to: $ratio',
      name: 'VineRecordingController',
      category: LogCategory.system,
    );
    _onStateChanged?.call();
  }

  void setFlashMode(FlashMode mode) {
    if (state == VideoRecorderState.recording) {
      Log.warning(
        'Cannot change flash mode while recording',
        name: 'VineRecordingController',
        category: LogCategory.system,
      );
      return;
    }

    _cameraInterface?.setFlashMode(mode);
    Log.info(
      '💡 Flash mode changed to: $mode',
      name: 'VineRecordingController',
      category: LogCategory.system,
    );
    _onStateChanged?.call();
  }

  /// Switch between front and rear cameras
  Future<void> switchCamera() async {
    Log.info(
      '🔄 VineRecordingController.switchCamera() called, current state: $_state',
      name: 'VineRecordingController',
      category: LogCategory.system,
    );

    if (_state == VideoRecorderState.recording) {
      Log.warning(
        'Cannot switch camera while recording',
        name: 'VineRecordingController',
        category: LogCategory.system,
      );
      return;
    }

    // If we're in paused state with a segment in progress, ensure it's properly stopped
    if (_currentSegmentStartTime != null) {
      Log.warning(
        'Cleaning up incomplete segment before camera switch',
        name: 'VineRecordingController',
        category: LogCategory.system,
      );
      _currentSegmentStartTime = null;
      _stopProgressTimer();
      _stopMaxDurationTimer();
    }

    try {
      Log.info(
        '🔄 Calling _cameraInterface?.switchCamera()...',
        name: 'VineRecordingController',
        category: LogCategory.system,
      );
      await _cameraInterface?.switchCamera();
      Log.info(
        '📱 Camera switched successfully at interface level',
        name: 'VineRecordingController',
        category: LogCategory.system,
      );

      // CRITICAL: Force state notification to trigger UI rebuild
      Log.info(
        '🔄 Calling _onStateChanged callback to trigger UI rebuild, callback=${_onStateChanged != null ? "exists" : "null"}',
        name: 'VineRecordingController',
        category: LogCategory.system,
      );
      _onStateChanged?.call();
      Log.info(
        '🔄 _onStateChanged callback completed',
        name: 'VineRecordingController',
        category: LogCategory.system,
      );
    } catch (e) {
      Log.error(
        'Failed to switch camera: $e',
        name: 'VineRecordingController',
        category: LogCategory.system,
      );
    }
  }

  /// Initialize the recording controller for the current platform
  Future<void> initialize() async {
    try {
      _setState(VideoRecorderState.idle);

      if (_cameraInterface != null) {
        _cameraInterface!.dispose();
        _cameraInterface = null;
        _cameraInitialized = false;
      }

      // Clean up any old recordings from previous sessions
      _cleanupRecordings();

      // Create platform-specific camera interface
      // TODO:

      // For non-mobile platforms, initialize here (mobile initialization handled above)
      if (!Platform.isIOS && !Platform.isAndroid) {
        await _cameraInterface!.initialize();
      }

      // Set up temp directory for segments
      if (!kIsWeb) {
        final tempDir = await _getTempDirectory();
        _tempDirectory = tempDir.path;
      }

      // Mark camera as initialized - UI can now show preview
      _cameraInitialized = true;

      Log.info(
        'VineRecordingController initialized for ${_getPlatformName()}',
        name: 'VineRecordingController',
        category: LogCategory.system,
      );
    } catch (e) {
      _setState(VideoRecorderState.error);
      _cameraInitialized = false;
      Log.error(
        'VineRecordingController initialization failed: $e',
        name: 'VineRecordingController',
        category: LogCategory.system,
      );
      rethrow;
    }
  }

  /// Start recording a new segment (press down)
  Future<void> startRecording() async {
    // DEBUG: Log controller instance for diagnosis
    Log.info(
      '🔍 startRecording called: controller hashCode=$hashCode, _state=$_state',
      name: 'VineRecordingController',
      category: LogCategory.system,
    );

    if (!canRecord) return;

    // Prevent starting if already recording
    if (_state == VideoRecorderState.recording) {
      Log.warning(
        'Already recording, ignoring start request',
        name: 'VineRecordingController',
        category: LogCategory.system,
      );
      return;
    }

    // On web, prevent multiple segments - MediaRecorder doesn't support pause/resume like mobile
    // Web needs continuous recording or a different concatenation approach
    if (kIsWeb && _segments.isNotEmpty) {
      Log.warning(
        'Multiple segments not supported on web - use single continuous recording',
        name: 'VineRecordingController',
        category: LogCategory.system,
      );
      return;
    }

    try {
      _setState(VideoRecorderState.recording);
      _currentSegmentStartTime = DateTime.now();

      // ProofMode proof will be generated after recording using Guardian Project native library

      // Normal segmented recording for all platforms
      final segmentPath = _generateSegmentPath();
      await _cameraInterface!.startRecordingSegment(segmentPath);

      // Start progress timer
      _startProgressTimer();

      // Set max duration timer if this is the first segment or we're close to limit
      _startMaxDurationTimer();

      Log.info(
        'Started recording segment ${_segments.length + 1}',
        name: 'VineRecordingController',
        category: LogCategory.system,
      );
    } catch (e) {
      // Reset state and clean up on error
      _currentSegmentStartTime = null;
      _stopProgressTimer();
      _stopMaxDurationTimer();
      _setState(VideoRecorderState.error);
      Log.error(
        'Failed to start recording: $e',
        name: 'VineRecordingController',
        category: LogCategory.system,
      );
      // Don't rethrow - handle gracefully in UI
    }
  }

  /// Stop recording current segment (release)
  Future<void> stopRecording() async {
    // Capture start time locally to prevent race conditions
    final segmentStartTime = _currentSegmentStartTime;

    // DEBUG: Log current state for diagnosis
    Log.info(
      '🔍 stopRecording called: _state=$_state, segmentStartTime=${segmentStartTime != null ? "set" : "NULL"}, controller hashCode=$hashCode',
      name: 'VineRecordingController',
      category: LogCategory.system,
    );

    if (_state != VideoRecorderState.recording || segmentStartTime == null) {
      Log.warning(
        'Not recording or no start time, ignoring stop request. State: $_state, HasStartTime: ${segmentStartTime != null}',
        name: 'VineRecordingController',
        category: LogCategory.system,
      );
      return;
    }

    // CRITICAL: Set state to paused IMMEDIATELY to prevent race conditions
    // where another stop request comes in while async camera stop is in progress.
    // The state check above will now correctly reject subsequent stop calls.
    // _setState(VideoRecordingState.paused);

    // Clear the segment start time immediately to prevent double-stop
    _currentSegmentStartTime = null;

    // Stop timers immediately to prevent them firing during async stop
    _stopProgressTimer();
    _stopMaxDurationTimer();

    try {
      var segmentEndTime = DateTime.now();
      var segmentDuration = segmentEndTime.difference(segmentStartTime);

      // For stop-motion: if user taps very quickly, wait for minimum duration
      // to ensure at least one frame is captured
      if (segmentDuration < minSegmentDuration) {
        final waitTime = minSegmentDuration - segmentDuration;
        Log.info(
          '🎬 Stop-motion mode: waiting ${waitTime.inMilliseconds}ms to capture frame',
          name: 'VineRecordingController',
          category: LogCategory.system,
        );
        await Future.delayed(waitTime);

        // Recalculate after waiting
        segmentEndTime = DateTime.now();
        segmentDuration = segmentEndTime.difference(segmentStartTime);
      }

      // Now we're guaranteed to have at least minSegmentDuration
      if (segmentDuration >= minSegmentDuration) {
        // For macOS in single recording mode, track segment but KEEP native recording going
        // The native recording only stops when finishRecording() is called
        if (!kIsWeb &&
            Platform.isMacOS &&
            _cameraInterface is MacOSCameraInterface) {
          final macOSInterface = _cameraInterface as MacOSCameraInterface;

          // Track the segment end time but DON'T stop native recording
          // This allows subsequent segments to continue from the same recording
          await macOSInterface.stopRecordingSegment();

          // Update total recorded duration for progress bar
          _totalRecordedDuration += segmentDuration;

          final virtualSegments = macOSInterface.getVirtualSegments();
          Log.info(
            '📱 macOS segment ${virtualSegments.length} tracked (${segmentDuration.inMilliseconds}ms) - native recording continues',
            name: 'VineRecordingController',
            category: LogCategory.system,
          );
        } else {
          // Normal segment recording for other platforms
          final filePath = await _cameraInterface!.stopRecordingSegment();

          if (filePath != null) {
            // CRITICAL: Copy segment to safe location immediately
            // CamerAwesome may delete previous recordings when starting new ones
            // This ensures all segments are preserved for concatenation
            Log.info(
              '📹 Segment ${_segments.length + 1} recorded to: $filePath',
              name: 'VineRecordingController',
              category: LogCategory.system,
            );

            // Wait for file to be written - CamerAwesome's stopRecording may return
            // before the file is fully flushed to disk, especially for short recordings
            final sourceFile = File(filePath);
            bool exists = await sourceFile.exists();

            // Retry up to 500ms waiting for file to appear (for stop-motion short taps)
            if (!exists) {
              Log.info(
                '📹 File not yet written, waiting for CamerAwesome to flush...',
                name: 'VineRecordingController',
                category: LogCategory.system,
              );
              for (int i = 0; i < 10 && !exists; i++) {
                await Future.delayed(const Duration(milliseconds: 50));
                exists = await sourceFile.exists();
              }
            }

            Log.info(
              '📹 Source file exists: $exists',
              name: 'VineRecordingController',
              category: LogCategory.system,
            );

            if (!exists) {
              // Even after waiting, file doesn't exist - recording truly failed
              Log.warning(
                '📹 Segment file does not exist after waiting, skipping segment',
                name: 'VineRecordingController',
                category: LogCategory.system,
              );
              // Don't add to _segments - this segment is invalid
            } else {
              String safeFilePath = filePath;
              try {
                final safeDir = await _getTempDirectory();
                final safePath =
                    '${safeDir.path}/safe_segment_${_segments.length + 1}_${DateTime.now().millisecondsSinceEpoch}.mov';
                Log.info(
                  '📹 Copying to safe path: $safePath',
                  name: 'VineRecordingController',
                  category: LogCategory.system,
                );
                final copiedFile = await sourceFile.copy(safePath);
                safeFilePath = copiedFile.path;
                Log.info(
                  '📹 Copied segment to safe location: $safeFilePath',
                  name: 'VineRecordingController',
                  category: LogCategory.system,
                );
              } catch (e) {
                Log.error(
                  '📹 Failed to copy segment to safe location: $e, using original path: $filePath',
                  name: 'VineRecordingController',
                  category: LogCategory.system,
                );
              }

              final segment = RecordingSegment(
                startTime: segmentStartTime,
                endTime: segmentEndTime,
                duration: segmentDuration,
                filePath: safeFilePath,
              );

              _segments.add(segment);
              _totalRecordedDuration += segmentDuration;

              Log.info(
                'Completed segment ${_segments.length}: ${segmentDuration.inMilliseconds}ms',
                name: 'VineRecordingController',
                category: LogCategory.system,
              );

              // CRITICAL: Force UI update after segment is added
              // The early _setState(paused) at the start of stopRecording happens
              // BEFORE the segment is added, so UI has stale hasSegments=false.
              // This ensures UI reflects the newly added segment.
              _onStateChanged?.call();
            }
          } else {
            Log.warning(
              'No file path returned from camera interface',
              name: 'VineRecordingController',
              category: LogCategory.system,
            );
          }
        }
      }

      // _currentSegmentStartTime already cleared at start of method
      _stopProgressTimer();
      _stopMaxDurationTimer();

      // Reset total duration to actual segments total (removing any in-progress time)
      // For macOS with virtual segments, use the virtual segments for duration calculation
      if (!kIsWeb &&
          Platform.isMacOS &&
          _cameraInterface is MacOSCameraInterface) {
        final macOSInterface = _cameraInterface as MacOSCameraInterface;
        final virtualSegments = macOSInterface.getVirtualSegments();
        _totalRecordedDuration = virtualSegments.fold<Duration>(
          Duration.zero,
          (total, segment) => total + segment.duration,
        );
      } else {
        _totalRecordedDuration = _segments.fold<Duration>(
          Duration.zero,
          (total, segment) => total + segment.duration,
        );
      }

      // Check if we've reached the maximum duration or if on web (single segment only)
      if (_totalRecordedDuration >= maxRecordingDuration || kIsWeb) {
        // _setState(VideoRecordingState.completed);
        Log.info(
          '📱 Recording completed - ${kIsWeb ? "web single segment" : "reached maximum duration"}',
          name: 'VineRecordingController',
          category: LogCategory.system,
        );
      } else {
        // _setState(VideoRecordingState.paused);
      }
    } catch (e) {
      // Reset state and clean up on error
      // Note: _currentSegmentStartTime already cleared at start of method
      _stopProgressTimer();
      _stopMaxDurationTimer();
      _setState(VideoRecorderState.error);
      Log.error(
        'Failed to stop recording: $e',
        name: 'VineRecordingController',
        category: LogCategory.system,
      );
      // Don't rethrow - handle gracefully in UI
    }
  }

  /// Get the recorded video path from macOS single recording mode.
  ///
  /// Refactored helper method that consolidates path discovery logic.
  /// Tries multiple sources in priority order:
  /// 1. Active recording completion (if still recording)
  /// 2. Current recording path (if already completed)
  /// 3. Virtual segments fallback (legacy path)
  ///
  /// Returns null if no valid recording is found.
  /// Throws exception if path discovery fails unexpectedly.
  Future<String?> _getMacOSRecordingPath(
    MacOSCameraInterface macOSInterface,
  ) async {
    // Try 1: If recording is still active, complete it first
    if (macOSInterface.isRecording) {
      try {
        final completedPath = await macOSInterface.completeRecording();
        if (completedPath != null && await File(completedPath).exists()) {
          Log.info(
            '📱 Got recording from active recording completion',
            name: 'VineRecordingController',
            category: LogCategory.system,
          );
          return completedPath;
        }
      } catch (e) {
        Log.error(
          'Failed to complete macOS recording: $e',
          name: 'VineRecordingController',
          category: LogCategory.system,
        );
      }
    }

    // Try 2: Check if we already have a recorded file
    if (macOSInterface.currentRecordingPath != null) {
      if (await File(macOSInterface.currentRecordingPath!).exists()) {
        Log.info(
          '📱 Got recording from currentRecordingPath',
          name: 'VineRecordingController',
          category: LogCategory.system,
        );
        return macOSInterface.currentRecordingPath;
      }
    }

    // Try 3: Check virtual segments as fallback
    final virtualSegments = macOSInterface.getVirtualSegments();
    if (virtualSegments.isNotEmpty && virtualSegments.first.filePath != null) {
      if (await File(virtualSegments.first.filePath!).exists()) {
        Log.info(
          '📱 Got recording from virtual segments',
          name: 'VineRecordingController',
          category: LogCategory.system,
        );
        return virtualSegments.first.filePath;
      }
    }

    return null;
  }

  /// Calculate crop transform for the given aspect ratio and resolution
  ExportTransform _calculateCropTransform(
    Size resolution,
    model.AspectRatio aspectRatio,
  ) {
    double cropX, cropY, cropWidth, cropHeight;

    switch (aspectRatio) {
      case model.AspectRatio.square:
        // Center crop to 1:1 (minimum dimension)
        final minDimension = resolution.width < resolution.height
            ? resolution.width
            : resolution.height;
        cropWidth = minDimension;
        cropHeight = minDimension;
        cropX = (resolution.width - cropWidth) / 2;
        cropY = (resolution.height - cropHeight) / 2;
        break;

      case model.AspectRatio.vertical:
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
        break;
    }

    Log.info(
      'Crop params: x=$cropX, y=$cropY, w=$cropWidth, h=$cropHeight',
      name: 'VineRecordingController',
      category: LogCategory.system,
    );

    return ExportTransform(
      x: cropX.round(),
      y: cropY.round(),
      width: cropWidth.round(),
      height: cropHeight.round(),
    );
  }

  /// Extract only the recorded segments from a macOS continuous recording
  /// Uses native code to cut out the paused portions based on virtual
  /// segment timestamps
  Future<File> _extractMacOSSegments(
    String inputPath,
    List<RecordingSegment> virtualSegments,
    DateTime recordingStartTime,
  ) async {
    if (virtualSegments.isEmpty) {
      throw Exception('No virtual segments to extract');
    }

    final tempDir = await getTemporaryDirectory();

    // If only one segment, just trim it directly with aspect ratio crop
    if (virtualSegments.length == 1) {
      final segment = virtualSegments.first;
      final startOffset = segment.startTime.difference(recordingStartTime);

      final outputPath =
          '${tempDir.path}/vine_extracted_${DateTime.now().millisecondsSinceEpoch}.mp4';

      Log.info(
        '📹 Extracting single macOS segment with crop',
        name: 'VineRecordingController',
        category: LogCategory.system,
      );

      // Get metadata for crop calculation
      final videoFile = EditorVideo.file(inputPath);
      final metaData = await ProVideoEditor.instance.getMetadata(videoFile);
      final resolution = metaData.resolution;

      Log.info(
        'Calculating crop for ${_aspectRatio.name} from resolution: ${resolution.width}x${resolution.height}',
        name: 'VineRecordingController',
        category: LogCategory.system,
      );

      final transform = _calculateCropTransform(resolution, _aspectRatio);

      final task = VideoRenderData(
        video: videoFile,
        startTime: startOffset,
        endTime: startOffset + segment.duration,
        transform: transform,
      );

      await ProVideoEditor.instance.renderVideoToFile(outputPath, task);

      final outputFile = File(outputPath);
      if (!await outputFile.exists()) {
        throw Exception('Extracted segment file does not exist');
      }

      Log.info(
        '📹 Single segment extracted successfully: $outputPath',
        name: 'VineRecordingController',
        category: LogCategory.system,
      );
      return outputFile;
    }

    // Multiple segments: extract each, then concatenate
    Log.info(
      '📹 Extracting ${virtualSegments.length} segments from macOS continuous recording',
      name: 'VineRecordingController',
      category: LogCategory.system,
    );

    final videoSegments = virtualSegments.map((segment) {
      final startOffset = segment.startTime.difference(recordingStartTime);

      return VideoSegment(
        video: EditorVideo.file(inputPath),
        startTime: startOffset,
        endTime: startOffset + segment.duration,
      );
    }).toList();

    // Get metadata for crop calculation
    final metaData = await ProVideoEditor.instance.getMetadata(
      videoSegments.first.video,
    );
    final resolution = metaData.resolution;

    Log.info(
      'Calculating crop for ${_aspectRatio.name} from resolution: ${resolution.width}x${resolution.height}',
      name: 'VineRecordingController',
      category: LogCategory.system,
    );

    final transform = _calculateCropTransform(resolution, _aspectRatio);

    final outputPath =
        '${tempDir.path}/vine_final_${DateTime.now().millisecondsSinceEpoch}.mp4';

    final task = VideoRenderData(
      videoSegments: videoSegments,
      transform: transform,
    );

    Log.info(
      '📹 Concatenating extracted segments with crop',
      name: 'VineRecordingController',
      category: LogCategory.system,
    );

    await ProVideoEditor.instance.renderVideoToFile(outputPath, task);

    final outputFile = File(outputPath);
    if (!await outputFile.exists()) {
      throw Exception('Final concatenated file does not exist');
    }

    Log.info(
      '📹 All segments extracted and concatenated: $outputPath',
      name: 'VineRecordingController',
      category: LogCategory.system,
    );
    return outputFile;
  }

  /// Generate native ProofMode proof for a video file
  Future<NativeProofData?> _generateNativeProof(File videoFile) async {
    try {
      // Check if native ProofMode is available on this platform
      final isAvailable = await NativeProofModeService.isAvailable();
      if (!isAvailable) {
        Log.info(
          '🔐 Native ProofMode not available on this platform',
          name: 'VineRecordingController',
          category: LogCategory.system,
        );
        return null;
      }

      Log.info(
        '🔐 Generating native ProofMode proof for: ${videoFile.path}',
        name: 'VineRecordingController',
        category: LogCategory.system,
      );

      // Generate proof using native library
      final proofHash = await NativeProofModeService.generateProof(
        videoFile.path,
      );
      if (proofHash == null) {
        Log.warning(
          '🔐 Native proof generation returned null',
          name: 'VineRecordingController',
          category: LogCategory.system,
        );
        return null;
      }

      Log.info(
        '🔐 Native proof hash: $proofHash',
        name: 'VineRecordingController',
        category: LogCategory.system,
      );

      // Read proof metadata from native library
      final metadata = await NativeProofModeService.readProofMetadata(
        proofHash,
      );
      if (metadata == null) {
        Log.warning(
          '🔐 Could not read native proof metadata',
          name: 'VineRecordingController',
          category: LogCategory.system,
        );
        return null;
      }

      Log.info(
        '🔐 Native proof metadata fields: ${metadata.keys.join(", ")}',
        name: 'VineRecordingController',
        category: LogCategory.system,
      );

      // Create NativeProofData from metadata
      final proofData = NativeProofData.fromMetadata(metadata);
      Log.info(
        '🔐 Native proof data created: ${proofData.verificationLevel}',
        name: 'VineRecordingController',
        category: LogCategory.system,
      );

      return proofData;
    } catch (e) {
      Log.error(
        '🔐 Native proof generation failed: $e',
        name: 'VineRecordingController',
        category: LogCategory.system,
      );
      return null;
    }
  }

  /// Extract individual segment files without concatenating
  /// Returns a list of ExtractedSegment with metadata for each segment
  /// For macOS: extracts from continuous recording using virtual segment timing
  /// For iOS: applies aspect ratio crop (hardware encoding works)
  /// For Android: returns original files with needsCrop=true (deferred encoding)
  Future<List<ExtractedSegment>> extractSegmentFiles() async {
    final results = <ExtractedSegment>[];

    // For macOS single recording mode, extract segments from continuous recording
    if (!kIsWeb &&
        Platform.isMacOS &&
        _cameraInterface is MacOSCameraInterface) {
      final macOSInterface = _cameraInterface as MacOSCameraInterface;

      if (macOSInterface.isSingleRecordingMode) {
        final virtualSegments = macOSInterface.getVirtualSegments();
        final recordingStartTime = macOSInterface.recordingStartTime;

        if (virtualSegments.isEmpty || recordingStartTime == null) {
          Log.warning(
            '📹 extractSegmentFiles: No virtual segments or start time',
            name: 'VineRecordingController',
            category: LogCategory.system,
          );
          return results;
        }

        // Get the recording path
        final recordingPath = await _getMacOSRecordingPath(macOSInterface);
        if (recordingPath == null) {
          Log.error(
            '📹 extractSegmentFiles: No recording path available',
            name: 'VineRecordingController',
            category: LogCategory.system,
          );
          return results;
        }

        final tempDir = await getTemporaryDirectory();

        // Probe actual video duration to validate segment timing
        // This handles edge cases where auto-stop triggers during pause
        double? videoDuration;
        try {
          final session = await FFprobeKit.getMediaInformation(recordingPath);
          final mediaInfo = session.getMediaInformation();
          if (mediaInfo != null) {
            final durationStr = mediaInfo.getDuration();
            if (durationStr != null && durationStr.isNotEmpty) {
              videoDuration = double.tryParse(durationStr);
            }
          }
        } catch (e) {
          Log.warning(
            '📹 Could not probe video duration: $e',
            name: 'VineRecordingController',
            category: LogCategory.system,
          );
        }

        Log.info(
          '📹 Extracting ${virtualSegments.length} segments without concatenation '
          '(preserving original resolution, video duration: ${videoDuration?.toStringAsFixed(2) ?? "unknown"}s)',
          name: 'VineRecordingController',
          category: LogCategory.system,
        );

        for (var i = 0; i < virtualSegments.length; i++) {
          final segment = virtualSegments[i];
          final startOffset = segment.startTime.difference(recordingStartTime);
          var startSec = startOffset.inMilliseconds / 1000.0;
          var durationSec = segment.duration.inMilliseconds / 1000.0;

          // Validate segment timing against actual video duration
          if (videoDuration != null) {
            if (startSec >= videoDuration) {
              Log.warning(
                '📹 Skipping segment $i: start time (${startSec.toStringAsFixed(2)}s) '
                'exceeds video duration (${videoDuration.toStringAsFixed(2)}s)',
                name: 'VineRecordingController',
                category: LogCategory.system,
              );
              continue;
            }

            // Trim segment duration if it would extend past video end
            final maxDuration = videoDuration - startSec;
            if (durationSec > maxDuration) {
              Log.info(
                '📹 Trimming segment $i duration from ${durationSec.toStringAsFixed(2)}s '
                'to ${maxDuration.toStringAsFixed(2)}s (video ends at ${videoDuration.toStringAsFixed(2)}s)',
                name: 'VineRecordingController',
                category: LogCategory.system,
              );
              durationSec = maxDuration;
            }

            // Skip segments with negligible duration after trimming
            if (durationSec < 0.1) {
              Log.warning(
                '📹 Skipping segment $i: duration too short after trimming (${durationSec.toStringAsFixed(2)}s)',
                name: 'VineRecordingController',
                category: LogCategory.system,
              );
              continue;
            }
          }

          final outputPath =
              '${tempDir.path}/segment_${i}_${DateTime.now().millisecondsSinceEpoch}.mp4';

          // Extract segment preserving original resolution - crop is applied at final export
          Log.info(
            '📹 Extracting segment $i: start=${startSec}s, duration=${durationSec}s',
            name: 'VineRecordingController',
            category: LogCategory.system,
          );

          final task = VideoRenderData(
            video: EditorVideo.file(recordingPath),
            startTime: Duration(seconds: startSec.toInt()),
            endTime: Duration(seconds: (startSec + durationSec).toInt()),
          );

          try {
            await ProVideoEditor.instance.renderVideoToFile(outputPath, task);

            final outputFile = File(outputPath);
            if (await outputFile.exists()) {
              results.add(
                ExtractedSegment(
                  file: outputFile,
                  duration: segment.duration,
                  needsCrop: false,
                  aspectRatio: null,
                ),
              );
              Log.info(
                '📹 Segment $i extracted: $outputPath',
                name: 'VineRecordingController',
                category: LogCategory.system,
              );
            }
          } catch (e) {
            Log.error(
              '📹 Failed to extract segment $i: ${e.toString()}',
              name: 'VineRecordingController',
              category: LogCategory.system,
            );
          }
        }

        return results;
      }
    }

    // For iOS/Android or non-single recording mode, use existing segment files
    if (_segments.isEmpty) {
      Log.warning(
        '📹 extractSegmentFiles: No segments available',
        name: 'VineRecordingController',
        category: LogCategory.system,
      );
      return results;
    }

    Log.info(
      '📹 Processing ${_segments.length} segment files',
      name: 'VineRecordingController',
      category: LogCategory.system,
    );

    for (var i = 0; i < _segments.length; i++) {
      final segment = _segments[i];
      if (segment.filePath == null) {
        Log.warning(
          '📹 Segment $i has no file path, skipping',
          name: 'VineRecordingController',
          category: LogCategory.system,
        );
        continue;
      }

      final file = File(segment.filePath!);
      if (!await file.exists()) {
        Log.warning(
          '📹 Segment $i file does not exist: ${segment.filePath}',
          name: 'VineRecordingController',
          category: LogCategory.system,
        );
        continue;
      }

      // Platform-specific handling:
      // Android: Skip encoding, return original file with crop metadata (deferred encoding)
      // iOS: Apply crop immediately (hardware encoding works fine with filters)
      if (!kIsWeb && Platform.isAndroid) {
        // Android: Defer cropping to export time for performance
        // CameraX already hardware-encoded the file, no need to re-encode
        results.add(
          ExtractedSegment(
            file: file,
            duration: segment.duration,
            needsCrop: true,
            aspectRatio: _aspectRatio,
          ),
        );
        Log.info(
          '📹 Segment $i: returning original file for deferred crop (Android), '
          'aspectRatio=${_aspectRatio.name}',
          name: 'VineRecordingController',
          category: LogCategory.system,
        );
      } else {
        // iOS and other platforms: Apply aspect ratio crop immediately
        try {
          final exportService = VideoExportService();
          final tempClip = RecordingClip(
            id: 'temp_segment_$i',
            video: EditorVideo.file(segment.filePath!),
            duration: segment.duration,
            recordedAt: segment.startTime,
          );
          final croppedPath = await exportService.concatenateSegments(
            [tempClip],
            aspectRatio: _aspectRatio,
            muteAudio: false,
          );
          results.add(
            ExtractedSegment(
              file: File(croppedPath),
              duration: segment.duration,
              needsCrop: false,
              aspectRatio: null,
            ),
          );
          Log.info(
            '📹 Segment $i processed: $croppedPath',
            name: 'VineRecordingController',
            category: LogCategory.system,
          );
        } catch (e) {
          Log.error(
            '📹 Failed to process segment $i: $e',
            name: 'VineRecordingController',
            category: LogCategory.system,
          );
        }
      }
    }

    return results;
  }

  /// Finish recording and return the final compiled video with optional native ProofMode data
  Future<(File?, NativeProofData?)> finishRecording() async {
    final startTime = DateTime.now();
    final returnValue = await (() async {
      try {
        //   _setState(VideoRecordingState.processing);

        // For macOS single recording mode, handle specially
        if (!kIsWeb &&
            Platform.isMacOS &&
            _cameraInterface is MacOSCameraInterface) {
          final macOSInterface = _cameraInterface as MacOSCameraInterface;

          // For single recording mode, extract only the virtual segment portions
          if (macOSInterface.isSingleRecordingMode) {
            final virtualSegments = macOSInterface.getVirtualSegments();
            final recordingStartTime = macOSInterface.recordingStartTime;

            Log.info(
              '📱 finishRecording: macOS single mode, isRecording=${macOSInterface.isRecording}, '
              'virtualSegments=${virtualSegments.length}, recordingStartTime=$recordingStartTime',
              name: 'VineRecordingController',
              category: LogCategory.system,
            );

            // Get the recording path from any available source
            final recordingPath = await _getMacOSRecordingPath(macOSInterface);
            if (recordingPath == null) {
              throw Exception(
                'No valid recording found for macOS single recording mode',
              );
            }

            File finalFile;

            // If we have virtual segments and a valid start time, extract only those portions
            if (virtualSegments.isNotEmpty && recordingStartTime != null) {
              Log.info(
                '📱 Extracting ${virtualSegments.length} virtual segments from continuous recording',
                name: 'VineRecordingController',
                category: LogCategory.system,
              );

              finalFile = await _extractMacOSSegments(
                recordingPath,
                virtualSegments,
                recordingStartTime,
              );
            } else {
              // Fallback: just apply aspect ratio crop (shouldn't normally happen)
              Log.warning(
                '📱 No virtual segments found, falling back to full video crop',
                name: 'VineRecordingController',
                category: LogCategory.system,
              );
              final exportService = VideoExportService();
              final tempClip = RecordingClip(
                id: 'temp_macos_fallback',
                video: EditorVideo.file(recordingPath),
                duration: Duration.zero, // Unknown duration
                recordedAt: DateTime.now(),
              );
              final croppedPath = await exportService.concatenateSegments(
                [tempClip],
                aspectRatio: _aspectRatio,
                muteAudio: false,
              );
              finalFile = File(croppedPath);
            }

            // _setState(VideoRecordingState.completed);
            macOSInterface.isSingleRecordingMode =
                false; // Clear flag after successful completion

            // Generate native ProofMode proof
            final nativeProof = await _generateNativeProof(finalFile);

            return (finalFile, nativeProof);
          }
        }

        // For non-single recording mode, stop any active recording
        if (_state == VideoRecorderState.recording) {
          await stopRecording();
        }

        // For multi-segment recording, check virtual segments first
        if (!kIsWeb &&
            Platform.isMacOS &&
            _cameraInterface is MacOSCameraInterface) {
          final macOSInterface = _cameraInterface as MacOSCameraInterface;
          final virtualSegments = macOSInterface.getVirtualSegments();

          // If we have virtual segments but no main segments, use the virtual ones
          if (_segments.isEmpty && virtualSegments.isNotEmpty) {
            _segments.addAll(virtualSegments);
            Log.info(
              'Using ${virtualSegments.length} virtual segments from macOS recording',
              name: 'VineRecordingController',
              category: LogCategory.system,
            );
          }
        }

        Log.info(
          '📱 finishRecording: hasSegments=$hasSegments, segments count=${_segments.length}',
          name: 'VineRecordingController',
          category: LogCategory.system,
        );

        // Debug: Log all segment details
        for (int i = 0; i < _segments.length; i++) {
          final segment = _segments[i];
          Log.info(
            '📱 Segment $i: duration=${segment.duration.inMilliseconds}ms, filePath=${segment.filePath}',
            name: 'VineRecordingController',
            category: LogCategory.system,
          );
        }

        if (!hasSegments) {
          throw Exception('No valid video segments found for compilation');
        }

        // For other platforms (iOS, Android), handle single segment with aspect ratio crop
        if (!kIsWeb &&
            _segments.length == 1 &&
            _segments.first.filePath != null) {
          final file = File(_segments.first.filePath!);
          if (await file.exists()) {
            // Apply aspect ratio crop to the video
            final exportService = VideoExportService();
            final tempClip = RecordingClip(
              id: 'temp_single_segment',
              video: EditorVideo.file(file.path),
              duration: _segments.first.duration,
              recordedAt: _segments.first.startTime,
            );
            final croppedPath = await exportService.concatenateSegments(
              [tempClip],
              aspectRatio: _aspectRatio,
              muteAudio: false,
            );
            final croppedFile = File(croppedPath);

            //  _setState(VideoRecordingState.completed);

            // Generate native ProofMode proof
            final nativeProof = await _generateNativeProof(croppedFile);

            return (croppedFile, nativeProof);
          }
        }

        // Concatenate multiple segments using VideoExportService
        if (_segments.isNotEmpty) {
          Log.info(
            '📹 Concatenating ${_segments.length} segments',
            name: 'VineRecordingController',
            category: LogCategory.system,
          );

          // Convert RecordingSegments to RecordingClips
          final clips = _segments
              .asMap()
              .entries
              .where((entry) => entry.value.filePath != null)
              .map(
                (entry) => RecordingClip(
                  id: 'segment_${entry.key}',
                  video: EditorVideo.file(entry.value.filePath!),
                  duration: entry.value.duration,
                  recordedAt: entry.value.startTime,
                  aspectRatio: _aspectRatio,
                ),
              )
              .toList();

          final exportService = VideoExportService();
          final outputPath = await exportService.concatenateSegments(
            clips,
            aspectRatio: _aspectRatio,
            muteAudio: false,
          );

          final concatenatedFile = File(outputPath);
          if (await concatenatedFile.exists()) {
            //  _setState(VideoRecordingState.completed);

            // Generate native ProofMode proof
            final nativeProof = await _generateNativeProof(concatenatedFile);

            return (concatenatedFile, nativeProof);
          }
        }

        throw Exception('No valid video segments found for compilation');
      } catch (e) {
        _setState(VideoRecorderState.error);
        Log.error(
          'Failed to finish recording: $e',
          name: 'VineRecordingController',
          category: LogCategory.system,
        );
        rethrow;
      }
    })();

    final endTime = DateTime.now();
    final duration = endTime.difference(startTime);

    Log.info(
      'finishRecording completed in ${duration.inMilliseconds}ms',
      name: 'VineRecordingController',
      category: LogCategory.system,
    );

    return returnValue;
  }

  /// Clean up recording files and prepare for new recording
  void cleanupFiles() {
    _cleanupRecordings();
  }

  /// Reset the recording session (but keep files for upload)
  void reset() {
    _stopProgressTimer();
    _stopMaxDurationTimer();

    // Don't clean up recording files here - they're needed for upload
    // Files will be cleaned up when starting a new recording session

    _segments.clear();
    _totalRecordedDuration = Duration.zero;
    _previouslyRecordedDuration = Duration.zero;
    _currentSegmentStartTime = null;

    // Check if we need to reinitialize before resetting state
    final wasInError = _state == VideoRecorderState.error;

    // Reset camera initialization flag if we're in error state
    if (wasInError) {
      _cameraInitialized = false;
    }

    // Reset state
    _setState(VideoRecorderState.idle);

    Log.debug(
      'Recording session reset',
      name: 'VineRecordingController',
      category: LogCategory.system,
    );
  }

  /// Clean up recording files and resources
  void _cleanupRecordings() {
    try {
      // Clean up platform-specific resources
      if (!kIsWeb &&
          Platform.isMacOS &&
          _cameraInterface is MacOSCameraInterface) {
        _cleanupMacOSRecording();
      } else {
        _cleanupMobileRecordings();
      }

      Log.debug(
        '🧹 Cleaned up recording resources',
        name: 'VineRecordingController',
        category: LogCategory.system,
      );
    } catch (e) {
      Log.error(
        'Error cleaning up recordings: $e',
        name: 'VineRecordingController',
        category: LogCategory.system,
      );
    }
  }

  /// Clean up macOS recording
  void _cleanupMacOSRecording() {
    final macOSInterface = _cameraInterface as MacOSCameraInterface;

    // Stop any active native recording to sync state with native layer
    // This prevents "Already recording" error when trying to record again
    if (macOSInterface.isRecording || macOSInterface.isSingleRecordingMode) {
      Log.debug(
        '🛑 Stopping active native recording during cleanup',
        name: 'VineRecordingController',
        category: LogCategory.system,
      );
      NativeMacOSCamera.stopRecording();
    }

    // Clean up recording files
    if (macOSInterface.currentRecordingPath != null) {
      try {
        // Clean up the recording file if it exists
        final file = File(macOSInterface.currentRecordingPath!);
        if (file.existsSync()) {
          file.deleteSync();
          Log.debug(
            '🧹 Deleted macOS recording file: ${macOSInterface.currentRecordingPath}',
            name: 'VineRecordingController',
            category: LogCategory.system,
          );
        }
      } catch (e) {
        Log.error(
          'Error deleting macOS recording file: $e',
          name: 'VineRecordingController',
          category: LogCategory.system,
        );
      }
    }

    // Reset the interface completely
    macOSInterface.reset();
  }

  /// Clean up mobile recordings
  void _cleanupMobileRecordings() {
    for (final segment in _segments) {
      if (segment.filePath != null) {
        try {
          final file = File(segment.filePath!);
          if (file.existsSync()) {
            file.deleteSync();
            Log.debug(
              '🧹 Deleted mobile recording file: ${segment.filePath}',
              name: 'VineRecordingController',
              category: LogCategory.system,
            );
          }
        } catch (e) {
          Log.error(
            'Error deleting mobile recording file: $e',
            name: 'VineRecordingController',
            category: LogCategory.system,
          );
        }
      }
    }
  }

  /// Release camera resources without fully disposing the controller.
  ///
  /// Call this when navigating away from the camera screen to free memory.
  /// The camera can be re-initialized later if the user returns.
  void releaseCamera() {
    Log.info(
      '📹 Releasing camera resources',
      name: 'VineRecordingController',
      category: LogCategory.video,
    );

    _cameraInterface?.dispose();
    _cameraInterface = null;
    _cameraInitialized = false;

    Log.info(
      '📹 Camera resources released',
      name: 'VineRecordingController',
      category: LogCategory.video,
    );
  }

  /// Dispose resources
  void dispose() {
    _disposed = true;
    _stopProgressTimer();
    _stopMaxDurationTimer();

    // Clean up all recordings
    _cleanupRecordings();

    _cameraInterface?.dispose();
  }

  // Private methods

  void _setState(VideoRecorderState newState) {
    if (_disposed) return;
    _state = newState;
    // Notify UI of state change
    _onStateChanged?.call();
  }

  void _startProgressTimer() {
    _stopProgressTimer();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!_disposed && _state == VideoRecorderState.recording) {
        // Update the total duration based on current segment time
        if (_currentSegmentStartTime != null) {
          final currentSegmentDuration = DateTime.now().difference(
            _currentSegmentStartTime!,
          );

          Duration previousDuration;
          // On macOS, use virtual segments for accumulated duration since _segments is empty
          if (!kIsWeb &&
              Platform.isMacOS &&
              _cameraInterface is MacOSCameraInterface) {
            final macOSInterface = _cameraInterface as MacOSCameraInterface;
            final virtualSegments = macOSInterface.getVirtualSegments();
            previousDuration = virtualSegments.fold<Duration>(
              Duration.zero,
              (total, segment) => total + segment.duration,
            );
          } else {
            previousDuration = _segments.fold<Duration>(
              Duration.zero,
              (total, segment) => total + segment.duration,
            );
          }

          _totalRecordedDuration = previousDuration + currentSegmentDuration;
        }

        // Notify UI of progress update
        _onStateChanged?.call();
      }
    });
  }

  void _stopProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  void _startMaxDurationTimer() {
    _stopMaxDurationTimer();
    final remainingTime = remainingDuration;
    if (remainingTime > Duration.zero) {
      _maxDurationTimer = Timer(remainingTime, () {
        if (_state == VideoRecorderState.recording) {
          Log.info(
            '📱 Recording completed - reached maximum duration',
            name: 'VineRecordingController',
            category: LogCategory.system,
          );

          // For macOS, handle auto-completion differently
          if (!kIsWeb &&
              Platform.isMacOS &&
              _cameraInterface is MacOSCameraInterface) {
            _handleMacOSAutoCompletion();
          } else {
            stopRecording();
          }
        }
      });
    }
  }

  /// Handle macOS recording auto-completion after max duration
  void _handleMacOSAutoCompletion() async {
    final macOSInterface = _cameraInterface as MacOSCameraInterface;

    // Stop the native recording first to get the file path
    final recordedPath = await macOSInterface.completeRecording();

    // Create a segment with the actual file path
    if (_currentSegmentStartTime != null && recordedPath != null) {
      final segmentEndTime = DateTime.now();
      final segmentDuration = segmentEndTime.difference(
        _currentSegmentStartTime!,
      );

      final segment = RecordingSegment(
        startTime: _currentSegmentStartTime!,
        endTime: segmentEndTime,
        duration: segmentDuration,
        filePath: recordedPath,
      );

      _segments.add(segment);
      _totalRecordedDuration += segmentDuration;

      Log.info(
        'Completed segment ${_segments.length} after auto-stop: ${segmentDuration.inMilliseconds}ms, path: $recordedPath',
        name: 'VineRecordingController',
        category: LogCategory.system,
      );
    } else if (_currentSegmentStartTime == null) {
      Log.warning(
        'Cannot create segment - no start time recorded',
        name: 'VineRecordingController',
        category: LogCategory.system,
      );
    } else if (recordedPath == null) {
      Log.error(
        'Cannot create segment - completeRecording returned null path',
        name: 'VineRecordingController',
        category: LogCategory.system,
      );
    }

    _currentSegmentStartTime = null;
    _stopProgressTimer();
    _stopMaxDurationTimer();

    // Set state to completed since we reached max duration
    //  _setState(VideoRecordingState.completed);
  }

  void _stopMaxDurationTimer() {
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;
  }

  String _generateSegmentPath() {
    if (kIsWeb) {
      return 'segment_${DateTime.now().millisecondsSinceEpoch}';
    }
    return '$_tempDirectory/vine_segment_${_segments.length + 1}_${DateTime.now().millisecondsSinceEpoch}.mov';
  }

  Future<Directory> _getTempDirectory() async {
    if (Platform.isIOS || Platform.isAndroid) {
      final directory = await getTemporaryDirectory();
      return directory;
    } else {
      // macOS/Windows temp directory
      return Directory.systemTemp;
    }
  }

  String _getPlatformName() {
    if (kIsWeb) return 'Web';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    return 'Unknown';
  } */
}
