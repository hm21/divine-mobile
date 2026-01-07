// ABOUTME: Video editor screen for adding text overlays and sound to recorded videos
// ABOUTME: Dark-themed interface with video preview, text editing, and sound selection

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openvine/providers/video_editor_provider.dart';
import 'package:openvine/widgets/video_editor/video_editor_bottom_bar.dart';
import 'package:openvine/widgets/video_editor/video_editor_clip_gallery.dart';
import 'package:openvine/widgets/video_editor/video_editor_processing_overlay.dart';
import 'package:openvine/widgets/video_editor/video_editor_progress_bar.dart';
import 'package:openvine/widgets/video_editor/video_editor_top_bar.dart';

/// Video editor screen for editing recorded video clips.
class VideoEditorScreen extends ConsumerStatefulWidget {
  /// Creates a video editor screen.
  const VideoEditorScreen({super.key, this.draftId});

  final String? draftId;

  @override
  ConsumerState<VideoEditorScreen> createState() => _VideoEditorScreenState();
}

class _VideoEditorScreenState extends ConsumerState<VideoEditorScreen> {
  late bool _isLoadingDraft = widget.draftId != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref
          .read(videoEditorProvider.notifier)
          .initialize(draftId: widget.draftId);
      if (!mounted) return;

      _isLoadingDraft = false;
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final isProcessing = ref.watch(
      videoEditorProvider.select((p) => p.isProcessing),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.black,
        statusBarIconBrightness: .light,
        statusBarBrightness: .dark,
      ),
      child: PopScope(
        canPop: !isProcessing,
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          backgroundColor: Colors.black,
          body: _isLoadingDraft
              ? Center(child: CircularProgressIndicator.adaptive())
              : Stack(
                  children: [
                    const SafeArea(
                      child: Column(
                        children: [
                          /// Top bar
                          VideoEditorTopBar(),

                          /// Main content area with clips
                          Expanded(child: VideoEditorClipGallery()),

                          /// Bottom bar
                          VideoEditorBottomBar(),

                          /// Progress bar
                          VideoProgressBar(),
                        ],
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: isProcessing
                          ? const VideoEditorProcessingOverlay()
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
