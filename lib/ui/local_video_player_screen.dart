import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../core/app_colors.dart';

class LocalVideoPlayerScreen extends StatefulWidget {
  final File file;

  const LocalVideoPlayerScreen({super.key, required this.file});

  @override
  State<LocalVideoPlayerScreen> createState() => _LocalVideoPlayerScreenState();
}

class _LocalVideoPlayerScreenState extends State<LocalVideoPlayerScreen> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _isError = false;
  bool _isBackgroundAudioEnabled = false;
  bool _isFloatingPiP = false;
  double _playbackSpeed = 1.0;
  bool _isLooping = false;

  Offset _pipPosition = const Offset(20, 100);

  static const MethodChannel _pipChannel = MethodChannel('com.boykta.app/pip');

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      final controller = VideoPlayerController.file(widget.file);
      _videoPlayerController = controller;
      await controller.initialize();

      controller.addListener(() {
        final isPlaying = _videoPlayerController?.value.isPlaying ?? false;
        _pipChannel.invokeMethod('setPlaying', {'isPlaying': isPlaying}).catchError((_) {});
      });
      _pipChannel.invokeMethod('setPlaying', {'isPlaying': true}).catchError((_) {});

      if (mounted) {
        setState(() {
          _chewieController = ChewieController(
            videoPlayerController: _videoPlayerController!,
            autoPlay: true,
            looping: _isLooping,
            allowFullScreen: true,
            allowPlaybackSpeedChanging: true,
            materialProgressColors: ChewieProgressColors(
              playedColor: AppColors.cyan,
              handleColor: AppColors.magenta,
              backgroundColor: Colors.white24,
              bufferedColor: Colors.white54,
            ),
          );
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isError = true);
      }
    }
  }

  Future<void> _enterSystemPiP() async {
    try {
      await _pipChannel.invokeMethod('enterPip');
    } catch (_) {
      // إذا لم يكن النظام يدعم Native PiP، نفعّل In-App Floating PiP
      setState(() {
        _isFloatingPiP = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تفعيل وضع النافذة العائمة المصغرة (PiP) 🪟'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _toggleBackgroundAudio() {
    setState(() {
      _isBackgroundAudioEnabled = !_isBackgroundAudioEnabled;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isBackgroundAudioEnabled
              ? 'تم تفعيل تشغيل الصوت في الخلفية 🎧 (سيستمر عند الخروج)'
              : 'تم إيقاف تشغيل الصوت في الخلفية',
        ),
        backgroundColor: _isBackgroundAudioEnabled ? AppColors.cyan : AppColors.surface,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showSpeedPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        final speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 15),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'سرعة التشغيل',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                ...speeds.map((s) => ListTile(
                      title: Text('${s}x', style: const TextStyle(color: Colors.white)),
                      trailing: _playbackSpeed == s ? const Icon(Icons.check_rounded, color: AppColors.cyan) : null,
                      onTap: () {
                        setState(() => _playbackSpeed = s);
                        _videoPlayerController?.setPlaybackSpeed(s);
                        Navigator.pop(ctx);
                      },
                    )),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _pipChannel.invokeMethod('setPlaying', {'isPlaying': false}).catchError((_) {});
    _chewieController?.dispose();
    if (!_isBackgroundAudioEnabled) {
      _videoPlayerController?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fileName = widget.file.path.split('/').last;

    if (_isFloatingPiP && _chewieController != null) {
      return Stack(
        children: [
          Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.picture_in_picture_alt_rounded, color: AppColors.cyan, size: 50),
                  const SizedBox(height: 15),
                  const Text('الفيديو يعمل حالياً في نافذة عائمة', style: TextStyle(color: Colors.white, fontSize: 16)),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.cyan, foregroundColor: Colors.black),
                    onPressed: () => setState(() => _isFloatingPiP = false),
                    icon: const Icon(Icons.fullscreen_rounded),
                    label: const Text('تكبير للشاشة الكاملة', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: _pipPosition.dx,
            top: _pipPosition.dy,
            child: GestureDetector(
              onPanUpdate: (details) {
                setState(() {
                  _pipPosition = Offset(
                    (_pipPosition.dx + details.delta.dx).clamp(0, MediaQuery.of(context).size.width - 240),
                    (_pipPosition.dy + details.delta.dy).clamp(50, MediaQuery.of(context).size.height - 180),
                  );
                });
              },
              child: Material(
                elevation: 10,
                borderRadius: BorderRadius.circular(14),
                color: Colors.black,
                child: Container(
                  width: 240,
                  height: 145,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.cyan, width: 1.5),
                  ),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: AspectRatio(
                          aspectRatio: _videoPlayerController!.value.aspectRatio,
                          child: VideoPlayer(_videoPlayerController!),
                        ),
                      ),
                      // شريط تحكم عائم مصغر
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Row(
                          children: [
                            GestureDetector(
                              onTap: () => setState(() => _isFloatingPiP = false),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                child: const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 16),
                              ),
                            ),
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: () => Navigator.pop(context),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                child: const Icon(Icons.close_rounded, color: Colors.white, size: 16),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        bottom: 4,
                        left: 4,
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              if (_videoPlayerController != null) {
                                _videoPlayerController!.value.isPlaying
                                    ? _videoPlayerController!.pause()
                                    : _videoPlayerController!.play();
                              }
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                            child: Icon(
                              (_videoPlayerController?.value.isPlaying ?? false) ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              color: AppColors.cyan,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          fileName,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          // زر تشغيل الصوت في الخلفية
          IconButton(
            icon: Icon(
              _isBackgroundAudioEnabled ? Icons.headset_rounded : Icons.headset_off_rounded,
              color: _isBackgroundAudioEnabled ? AppColors.cyan : Colors.white70,
            ),
            tooltip: 'تشغيل الصوت في الخلفية',
            onPressed: _toggleBackgroundAudio,
          ),
          // زر النافذة العائمة (Picture-in-Picture)
          IconButton(
            icon: const Icon(Icons.picture_in_picture_alt_rounded, color: AppColors.cyan),
            tooltip: 'وضع صورة في صورة (PiP)',
            onPressed: _enterSystemPiP,
          ),
          // زر سرعة التشغيل
          IconButton(
            icon: const Icon(Icons.speed_rounded, color: Colors.white70),
            tooltip: 'سرعة التشغيل',
            onPressed: _showSpeedPicker,
          ),
        ],
      ),
      body: Center(
        child: _isError
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: AppColors.orange, size: 50),
                  const SizedBox(height: 15),
                  const Text('تعذر تشغيل هذا الملف', style: TextStyle(color: Colors.white, fontSize: 16)),
                  const SizedBox(height: 5),
                  const Text('قد يكون الملف تالفاً أو بصيغة غير مدعومة', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ],
              )
            : _chewieController != null && _chewieController!.videoPlayerController.value.isInitialized
                ? Chewie(controller: _chewieController!)
                : const CircularProgressIndicator(color: AppColors.cyan),
      ),
    );
  }
}
