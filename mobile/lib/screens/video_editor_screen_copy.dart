// ABOUTME: Video editor screen for adding text overlays and sound to recorded videos
// ABOUTME: Dark-themed interface with video preview, text editing, and sound selection
// FIXME(@hm21): Delete that file
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:openvine/platform_io.dart';
import 'package:openvine/widgets/sound_picker/sound_picker_modal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:pro_video_editor/pro_video_editor.dart';
import 'package:openvine/screens/pure/video_metadata_screen_pure.dart';
import 'package:openvine/utils/unified_logger.dart';

import '../providers/sound_library_service_provider.dart';
import '../services/video_editor/video_editor_service.dart';

class VideoEditorScreen extends ConsumerStatefulWidget {
  const VideoEditorScreen({super.key, required this.videoPath});

  final String videoPath;

  @override
  ConsumerState<VideoEditorScreen> createState() => _VideoEditorScreenState();
}

class _VideoEditorScreenState extends ConsumerState<VideoEditorScreen> {
  late final VideoEditorService _videoEditorService;

  bool _isVideoInitialized = false;

  VideoRenderData? _renderTask;

  @override
  void initState() {
    super.initState();
    Log.info(
      '📹 VideoEditorScreen.initState() START - videoPath: ${widget.videoPath}',
      category: LogCategory.video,
    );

    _videoEditorService = VideoEditorService(
      videoPath: widget.videoPath,
      context: context,
      onStateChanged: () {
        if (mounted) setState(() {});
      },
    );

    _videoEditorService.initializePlayer();
    Log.info(
      '📹 VideoEditorScreen.initState() END',
      category: LogCategory.video,
    );
  }

  @override
  void dispose() {
    _videoEditorService.dispose();
    super.dispose();
  }

  /// Load and play the selected sound, synced with video
  Future<void> _loadAndPlaySound(String? soundId) async {
    await _videoEditorService.loadAndPlaySound(soundId);

    if (soundId == null) return;

    // Get the sound's asset path
    final soundService = await ref.read(soundLibraryServiceProvider.future);
    final sound = soundService.getSoundById(soundId);

    if (sound == null) {
      Log.warning('Sound not found: $soundId', category: LogCategory.video);
      return;
    }

    try {
      String filePath;

      // Load the audio - handle both asset paths and file paths
      if (sound.assetPath.startsWith('/') ||
          sound.assetPath.startsWith('file://')) {
        // Custom sound - file path
        filePath = sound.assetPath.replaceFirst('file://', '');
      } else {
        // Bundled asset - copy to temp file for reliable playback on desktop
        final tempDir = await getTemporaryDirectory();
        final extension = sound.assetPath.split('.').last;
        filePath = '${tempDir.path}/editor_${sound.id}.$extension';

        final tempFile = File(filePath);
        if (!await tempFile.exists()) {
          final assetData = await rootBundle.load(sound.assetPath);
          await tempFile.writeAsBytes(assetData.buffer.asUint8List());
        }
      }

      await _videoEditorService.playSound(filePath, sound.title);
    } catch (e) {
      Log.error('Failed to load sound: $e', category: LogCategory.video);
    }
  }

  void handleAddSound() async {
    // Pause video and audio while selecting sound
    await _videoEditorService.videoController?.pause();
    await _videoEditorService.pauseAudio();

    // Wait for sounds to load
    final soundServiceAsync = await ref.read(
      soundLibraryServiceProvider.future,
    );

    if (!mounted) return;

    /*  String? selectedSoundId; */

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SoundPickerModal(
          sounds: soundServiceAsync.sounds,
          selectedSoundId: _videoEditorService.selectedSoundId,
          onSoundSelected: (soundId) {
            _videoEditorService.selectSound(soundId);
            // Play the selected sound in preview
            _loadAndPlaySound(soundId);
            Navigator.of(context).pop();
          },
        ),
      ),
    );

    // Load and play sound after returning from sound picker
    // This ensures the navigation is complete before we start playing
    if (mounted) {
      await _videoEditorService.videoController?.play();
      // Audio will resume via _loadAndPlaySound if a sound is selected
    }
  }

  Future<void> _createDraft(String draftId, String outputPath) async {
    // Get the aspect ratio from recording state
    /*     final recordingState = ref.read(videoRecorderProvider);
    final aspectRatio = recordingState.aspectRatio; */
    // TODO(@hm21): Only create a draft if one does not already exist.

    // Create a draft for the edited video (with overlays burned in)
    /*   final draft = VineDraft.create(
      id: draftId,
      videoFile: File(outputPath),
      title: '',
      description: '',
      hashtags: [],
      frameCount: 0,
      selectedApproach: 'video',
      aspectRatio: aspectRatio,
    ); 

    // Create draft storage service
    final prefs = await SharedPreferences.getInstance();
    final draftService = DraftStorageService(prefs);

    await draftService.saveDraft(draft);
    Log.info(
      '📹 Created draft with ID: ${draft.id}',
      category: LogCategory.video,
    );*/
  }

  /// We open the metadata screen in parallel with the render task. This
  /// improves the user experience significantly, as there is no loading
  /// screen or it is very short.
  void _openMetadataScreen(String draftId) async {
    // Navigate to metadata screen
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => VideoMetadataScreenPure(draftId: draftId),
      ),
    );

    if (_renderTask == null) return;

    await ProVideoEditor.instance.cancel(_renderTask!.id);
  }

  /// Generates the final video based on the given [parameters].
  ///
  /// Applies blur, color filters, cropping, rotation, flipping, and trimming
  /// before exporting using FFmpeg. Measures and stores the generation time.
  Future<void> _generateVideo(CompleteParameters parameters) async {
    Log.info(
      '📹 VideoEditorScreen: Creating draft for video: ${widget.videoPath}',
      category: LogCategory.video,
    );

    final directory = await getTemporaryDirectory();
    final now = DateTime.now().millisecondsSinceEpoch;
    final outputPath = '${directory.path}/video_$now.mp4';
    final draftId = 'draft_${now}';

    _openMetadataScreen(draftId);

    unawaited(_videoEditorService.videoController?.pause());
    unawaited(_videoEditorService.audioService.pause());

    final AudioTrack? customAudioTrack = parameters.customAudioTrack;
    final double volumeBalance = customAudioTrack?.volumeBalance ?? 0;
    double overlayVolume = 1;
    double originalVolume = 1;
    if (volumeBalance < 0) {
      overlayVolume += volumeBalance;
    } else {
      originalVolume -= volumeBalance;
    }

    _renderTask = VideoRenderData(
      id: _videoEditorService.taskId,
      video: _videoEditorService.video,
      outputFormat: _videoEditorService.outputFormat,
      enableAudio:
          _videoEditorService.proVideoController?.isAudioEnabled ?? true,
      imageBytes: parameters.layers.isNotEmpty ? parameters.image : null,
      blur: parameters.blur,
      colorMatrixList: parameters.colorFilters,
      startTime: parameters.startTime,
      endTime: parameters.endTime,
      transform: parameters.isTransformed
          ? ExportTransform(
              width: parameters.cropWidth,
              height: parameters.cropHeight,
              rotateTurns: parameters.rotateTurns,
              x: parameters.cropX,
              y: parameters.cropY,
              flipX: parameters.flipX,
              flipY: parameters.flipY,
            )
          : null,
      customAudioPath: await _videoEditorService.audioService
          .safeCustomAudioPath(customAudioTrack),
      originalAudioVolume: originalVolume,
      customAudioVolume: overlayVolume,
      // bitrate: _videoMetadata.bitrate,
    );

    try {
      await ProVideoEditor.instance.renderVideoToFile(outputPath, _renderTask!);

      await _createDraft(draftId, outputPath);

      if (mounted) {
        // Dispose video controller to free memory before navigating
        // The metadata screen will create its own player
        _videoEditorService.videoController?.dispose();
        _videoEditorService.stopAudio();
        setState(() {
          _isVideoInitialized = false;
        });
      }

      // Call original callback if exists
    } on RenderCanceledException {
      // TODO(@hm21): Handle cancel-task
      return;
    } catch (e) {
      Log.error('Failed to create draft: $e', category: LogCategory.video);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save video: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _handleCloseEditor(EditorMode editorMode) async {
    if (editorMode != EditorMode.main) return Navigator.pop(context);

    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    Log.info(
      '📹 VideoEditorScreen.build() START - isVideoInitialized: $_isVideoInitialized',
      category: LogCategory.video,
    );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: _videoEditorService.proVideoController == null
          ? const Center(child: CircularProgressIndicator())
          : _buildEditor(),
    );
  }

  Widget _buildEditor() {
    return ProImageEditor.video(
      _videoEditorService.proVideoController!,
      key: _videoEditorService.editorKey,
      configs: _videoEditorService.configs,
      callbacks: _videoEditorService.getEditorCallbacks().copyWith(
        onCompleteWithParameters: _generateVideo,
        onCloseEditor: _handleCloseEditor,
      ),
    );
  }
}
