// ABOUTME: Screen for adjusting audio timing/offset for video editor.
// ABOUTME: Displays video preview with audio segment selector overlay.

import 'package:divine_ui/divine_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';
import 'package:go_router/go_router.dart';
import 'package:openvine/models/audio_event.dart';
import 'package:openvine/providers/sounds_providers.dart';
import 'package:openvine/widgets/video_editor/audio_editor/video_editor_audio_chip.dart';

/// Screen for adjusting audio timing/offset in the video editor.
///
/// This screen is shown after selecting audio, allowing users to
/// set the start position of the audio track relative to the video.
class VideoAudioEditorTimingScreen extends ConsumerStatefulWidget {
  /// Creates the audio timing screen.
  const VideoAudioEditorTimingScreen({super.key, required this.audio});

  /// The selected audio to adjust timing for.
  final AudioEvent audio;

  /// Route name for navigation.
  static const routeName = 'video-audio-timing';

  /// Route path.
  static const path = '/video-audio-timing';

  @override
  ConsumerState<VideoAudioEditorTimingScreen> createState() =>
      _VideoAudioEditorTimingScreenState();
}

class _VideoAudioEditorTimingScreenState
    extends ConsumerState<VideoAudioEditorTimingScreen> {
  // TODO: Implement actual audio playback and timing adjustment.
  double _startOffset = 0;

  @override
  void initState() {
    super.initState();
    // Temporarily select the audio so the chip displays it
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(selectedSoundProvider.notifier).select(widget.audio);
    });
  }

  void _deleteAudio() {
    ref.read(selectedSoundProvider.notifier).clear();
    context.pop();
  }

  void _confirmSelection() {
    // TODO: Apply the timing offset to the selected sound.
    ref.read(selectedSoundProvider.notifier).select(widget.audio);
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Scrim overlay (65% black as per Figma)
            const ColoredBox(
              color: Color(0xA6000000), // rgba(0,0,0,0.65)
            ),

            // Content
            SafeArea(
              child: Column(
                children: [
                  // Top bar
                  _TopBar(onDelete: _deleteAudio, onConfirm: _confirmSelection),

                  const Spacer(),

                  // Bottom controls
                  _BottomControls(
                    startOffset: _startOffset,
                    onOffsetChanged: (offset) {
                      setState(() {
                        _startOffset = offset;
                      });
                    },
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

/// Top navigation bar with delete button, audio chip, and confirm button.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.onDelete, required this.onConfirm});

  final VoidCallback onDelete;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          // Delete button (red/coral)
          _CircleButton(
            // TODO(l10n): Replace with context.l10n when localization is added.
            semanticsLabel: 'Remove audio',
            iconPath: 'assets/icon/trash.svg',
            backgroundColor: const Color(0xFFE53935),
            iconColor: VineTheme.whiteText,
            onTap: onDelete,
          ),

          const SizedBox(width: 12),

          // Audio chip (centered, flexible)
          Expanded(
            child: VideoEditorAudioChip(
              onTap: () {
                // TODO: Allow re-selecting audio from this screen.
              },
            ),
          ),

          const SizedBox(width: 12),

          // Confirm button (white)
          _CircleButton(
            // TODO(l10n): Replace with context.l10n when localization is added.
            semanticsLabel: 'Confirm audio selection',
            iconPath: 'assets/icon/Check.svg',
            backgroundColor: VineTheme.whiteText,
            iconColor: VineTheme.backgroundColor,
            onTap: onConfirm,
          ),
        ],
      ),
    );
  }
}

/// Bottom controls with instruction text and timeline selector.
class _BottomControls extends StatelessWidget {
  const _BottomControls({
    required this.startOffset,
    required this.onOffsetChanged,
  });

  final double startOffset;
  final ValueChanged<double> onOffsetChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 28,
      children: [
        // Instruction text
        Text(
          // TODO(l10n): Replace with context.l10n when localization is added.
          'Select the audio segment for your video',
          style: VineTheme.bodyMediumFont().copyWith(
            color: VineTheme.whiteText,
          ),
          textAlign: TextAlign.center,
        ),

        // Video duration timeline (top bar with green segment)
        Padding(
          padding: const .symmetric(horizontal: 16.0),
          child: _VideoDurationTimeline(startOffset: startOffset),
        ),

        // Audio waveform with draggable selection
        _AudioWaveformSelector(
          startOffset: startOffset,
          onOffsetChanged: onOffsetChanged,
        ),
      ],
    );
  }
}

/// Video duration timeline showing where the selected segment will play.
class _VideoDurationTimeline extends StatelessWidget {
  const _VideoDurationTimeline({required this.startOffset});

  final double startOffset;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width - 32;
    const segmentWidthRatio = 0.25;
    final segmentWidth = screenWidth * segmentWidthRatio;

    return Container(
      height: 8,
      decoration: BoxDecoration(
        color: VineTheme.whiteText.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Stack(
        children: [
          Positioned(
            left: startOffset * (screenWidth - segmentWidth),
            child: Container(
              width: segmentWidth,
              height: 8,
              decoration: BoxDecoration(
                color: VineTheme.vineGreen,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Audio waveform with draggable green selection area.
class _AudioWaveformSelector extends StatelessWidget {
  const _AudioWaveformSelector({
    required this.startOffset,
    required this.onOffsetChanged,
  });

  final double startOffset;
  final ValueChanged<double> onOffsetChanged;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width - 32;
    // Selection area represents portion of audio that fits video duration
    const selectionWidthRatio = 0.35;
    final selectionWidth = screenWidth * selectionWidthRatio;

    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        final renderBox = context.findRenderObject()! as RenderBox;
        final localX = renderBox.globalToLocal(details.globalPosition).dx;
        final maxOffset = screenWidth - selectionWidth;
        final newOffset = ((localX - selectionWidth / 2) / maxOffset).clamp(
          0.0,
          1.0,
        );
        onOffsetChanged(newOffset);
      },
      onTapDown: (details) {
        final renderBox = context.findRenderObject()! as RenderBox;
        final localX = renderBox.globalToLocal(details.globalPosition).dx;
        final maxOffset = screenWidth - selectionWidth;
        final newOffset = ((localX - selectionWidth / 2) / maxOffset).clamp(
          0.0,
          1.0,
        );
        onOffsetChanged(newOffset);
      },
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          color: VineTheme.backgroundColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Stack(
          children: [
            // Full waveform (white bars)
            Positioned.fill(
              child: CustomPaint(
                painter: _WaveformPainter(barColor: VineTheme.whiteText),
              ),
            ),

            // Green selection overlay with yellow border
            Positioned(
              left: startOffset * (screenWidth - selectionWidth),
              top: 0,
              bottom: 0,
              child: Container(
                width: selectionWidth,
                decoration: BoxDecoration(
                  color: VineTheme.vineGreen,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFFFFEB3B), // Yellow border
                    width: 3,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: CustomPaint(
                    painter: _WaveformPainter(
                      barColor: VineTheme.whiteText.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Circular icon button with customizable colors.
class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.semanticsLabel,
    required this.iconPath,
    required this.backgroundColor,
    required this.iconColor,
    required this.onTap,
  });

  final String semanticsLabel;
  final String iconPath;
  final Color backgroundColor;
  final Color iconColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onTap != null;

    return Semantics(
      label: semanticsLabel,
      button: true,
      enabled: isEnabled,
      child: Opacity(
        opacity: isEnabled ? 1 : 0.32,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: backgroundColor,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: SvgPicture.asset(
                iconPath,
                width: 24,
                height: 24,
                colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints audio waveform bars with pseudo-random heights.
class _WaveformPainter extends CustomPainter {
  _WaveformPainter({required this.barColor});

  final Color barColor;

  static const _barWidth = 4.0;
  static const _barSpacing = 3.0;
  static const _barStep = _barWidth + _barSpacing;

  @override
  void paint(Canvas canvas, Size size) {
    final barCount = (size.width / _barStep).floor();
    final halfHeight = size.height / 2;

    final paint = Paint()
      ..color = barColor
      ..style = PaintingStyle.fill;

    // Generate pseudo-random heights for visual interest
    for (var i = 0; i < barCount; i++) {
      final x = i * _barStep;
      // Create varied waveform pattern
      final seed = (i * 17 + 7) % 23;
      final heightFactor = 0.2 + 0.8 * (seed / 23);
      final barHeight = size.height * 0.45 * heightFactor;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(x + _barWidth / 2, halfHeight),
            width: _barWidth,
            height: barHeight.clamp(4.0, size.height * 0.9),
          ),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) {
    return oldDelegate.barColor != barColor;
  }
}
