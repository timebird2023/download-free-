import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../core/app_colors.dart';
import '../services/backend_service.dart';

class WatchVideoScreen extends StatefulWidget {
  final yt.Video video;

  const WatchVideoScreen({super.key, required this.video});

  @override
  State<WatchVideoScreen> createState() => _WatchVideoScreenState();
}

class _WatchVideoScreenState extends State<WatchVideoScreen> {
  final BackendService _backend = BackendService();
  final yt.YoutubeExplode _yt = yt.YoutubeExplode();

  late yt.Video _currentVideo;
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;

  bool _isLoadingPlayer = true;
  String? _playerError;
  bool _isBackgroundAudioEnabled = false;
  bool _isFloatingPiP = false;
  Offset _pipPosition = const Offset(20, 100);

  final ScrollController _relatedScrollController = ScrollController();
  bool _isLoadingExtraction = false;
  List<yt.Video> _relatedVideos = [];
  yt.VideoSearchList? _relatedSearchPage;
  bool _isLoadingRelated = true;
  bool _isLoadingMoreRelated = false;

  static const MethodChannel _pipChannel = MethodChannel('com.boykta.app/pip');

  @override
  void initState() {
    super.initState();
    _currentVideo = widget.video;
    _initDirectStreamPlayer(_currentVideo);
    _fetchRelatedVideos();

    _relatedScrollController.addListener(() {
      if (_relatedScrollController.position.pixels >= _relatedScrollController.position.maxScrollExtent - 200) {
        _loadMoreRelatedVideos();
      }
    });
  }

  /// التقاط رابط البث المباشر وتشغيله عبر مشغل الفيديو الأصلي Native Video Player (Chewie)
  Future<void> _initDirectStreamPlayer(yt.Video video) async {
    if (!mounted) return;
    setState(() {
      _isLoadingPlayer = true;
      _playerError = null;
    });

    // تحرير المشغلات السابقة بأمان
    try {
      _chewieController?.pause();
      _chewieController?.dispose();
      _chewieController = null;
      await _videoPlayerController?.dispose();
      _videoPlayerController = null;
    } catch (_) {}

    try {
      final streamData = await _backend.getPlayableStream(video.id.value);
      final String streamUrl = streamData['url'] as String;

      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(streamUrl),
        httpHeaders: const {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 13; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.6367.82 Mobile Safari/537.36',
          'Referer': 'https://www.youtube.com/',
        },
      );

      await _videoPlayerController!.initialize();

      if (!mounted) return;

      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController!,
        autoPlay: true,
        looping: false,
        allowFullScreen: true,
        allowPlaybackSpeedChanging: true,
        showControls: true,
        aspectRatio: _videoPlayerController!.value.aspectRatio > 0
            ? _videoPlayerController!.value.aspectRatio
            : 16 / 9,
        materialProgressColors: ChewieProgressColors(
          playedColor: AppColors.cyan,
          handleColor: AppColors.cyan,
          backgroundColor: Colors.white24,
          bufferedColor: Colors.white54,
        ),
      );

      setState(() {
        _isLoadingPlayer = false;
      });
    } catch (e) {
      debugPrint('خطأ في تشغيل الفيديو المباشر: $e');
      if (mounted) {
        setState(() {
          _isLoadingPlayer = false;
          _playerError = 'تعذر تشغيل هذا المقطع مباشرة عبر خادم البث، يرجى إعادة المحاولة أو التحميل.';
        });
      }
    }
  }

  Future<void> _fetchRelatedVideos() async {
    try {
      var results = await _yt.search.search(_currentVideo.author);
      var filteredList = results.whereType<yt.Video>().where((v) => v.id.value != _currentVideo.id.value).toList();

      if (filteredList.isEmpty) {
        String shortTitle = _currentVideo.title.split(' ').take(3).join(' ');
        results = await _yt.search.search(shortTitle);
        filteredList = results.whereType<yt.Video>().where((v) => v.id.value != _currentVideo.id.value).toList();
      }

      if (mounted) {
        setState(() {
          _relatedSearchPage = results;
          _relatedVideos = filteredList;
          _isLoadingRelated = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingRelated = false);
    }
  }

  Future<void> _loadMoreRelatedVideos() async {
    if (_isLoadingMoreRelated) return;
    if (_relatedSearchPage?.nextPage != null) {
      setState(() => _isLoadingMoreRelated = true);
      try {
        final next = await _relatedSearchPage!.nextPage();
        if (next != null) {
          setState(() {
            _relatedSearchPage = next;
            _relatedVideos.addAll(next.whereType<yt.Video>());
          });
        }
      } catch (e) {
        debugPrint('Error loading more related: $e');
      } finally {
        if (mounted) setState(() => _isLoadingMoreRelated = false);
      }
    }
  }

  void _changeVideo(yt.Video newVideo) {
    if (_currentVideo.id.value == newVideo.id.value) return;

    setState(() {
      _currentVideo = newVideo;
      _isLoadingRelated = true;
      _relatedVideos.clear();
    });

    _initDirectStreamPlayer(newVideo);
    _fetchRelatedVideos();
  }

  List<Map<String, dynamic>> _processFormats(List<Map<String, dynamic>> formats) {
    if (formats.isEmpty) return [];
    var uniqueFormats = <String, Map<String, dynamic>>{};
    for (var f in formats) {
      final key = f['quality_name']?.toString() ?? '';
      // نفضل الدفق المدمج مسبقاً (muxed) أو صيغة mp4 (H.264) لتفادي أي مشاكل ترميز
      if (!uniqueFormats.containsKey(key)) {
        uniqueFormats[key] = f;
      } else {
        final existing = uniqueFormats[key]!;
        if (existing['needs_merge'] == true && f['needs_merge'] == false) {
          uniqueFormats[key] = f;
        } else if (existing['container'] != 'mp4' && f['container'] == 'mp4') {
          uniqueFormats[key] = f;
        }
      }
    }
    var sortedList = uniqueFormats.values.toList();

    sortedList.sort((a, b) {
      int orderA = a['quality_order'] is int
          ? a['quality_order']
          : (int.tryParse(a['quality_order']?.toString() ?? '') ?? 0);
      int orderB = b['quality_order'] is int
          ? b['quality_order']
          : (int.tryParse(b['quality_order']?.toString() ?? '') ?? 0);

      if (orderA != 0 && orderB != 0 && orderA != orderB) {
        return orderB.compareTo(orderA); // أعلى جودة أولاً (1080p FHD)
      }
      double sizeA = double.tryParse(a['size'].toString()) ?? 0.0;
      double sizeB = double.tryParse(b['size'].toString()) ?? 0.0;
      return sizeB.compareTo(sizeA); // الأكبر حجماً أولاً
    });
    return sortedList;
  }

  Future<void> _handleExtraction() async {
    setState(() => _isLoadingExtraction = true);
    _chewieController?.pause();

    try {
      final result = await _backend.extractMediaLinks(_currentVideo.url);

      final String videoTitle = result['title'] as String;
      final String highestAudioUrl = result['highestAudioUrl'] as String;
      final int? highestAudioTag = result['highestAudioTag'] as int?;

      final List<Map<String, dynamic>> videoList = _processFormats(List<Map<String, dynamic>>.from(result['video'] ?? []));
      final List<Map<String, dynamic>> audioList = _processFormats(List<Map<String, dynamic>>.from(result['audio'] ?? []));

      if (mounted && (videoList.isNotEmpty || audioList.isNotEmpty)) {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) {
            return FormatSelectionSheet(
              title: videoTitle,
              highestAudioUrl: highestAudioUrl,
              highestAudioTag: highestAudioTag,
              videoId: _currentVideo.id.value,
              videoFormats: videoList,
              audioFormats: audioList,
            );
          },
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('الرابط محمي أو لا توجد جودات متاحة حالياً.'))
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('الخطأ: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: AppColors.orange,
            duration: const Duration(seconds: 4),
          )
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingExtraction = false);
    }
  }

  Future<void> _enterSystemPiP() async {
    try {
      await _pipChannel.invokeMethod('enterPip');
    } catch (_) {
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

  @override
  void dispose() {
    if (!_isBackgroundAudioEnabled) {
      _chewieController?.dispose();
      _videoPlayerController?.dispose();
    }
    _relatedScrollController.dispose();
    _yt.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isFloatingPiP && _videoPlayerController != null && _videoPlayerController!.value.isInitialized) {
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
                              _videoPlayerController!.value.isPlaying
                                  ? _videoPlayerController!.pause()
                                  : _videoPlayerController!.play();
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                            child: Icon(
                              _videoPlayerController!.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _currentVideo.title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isBackgroundAudioEnabled ? Icons.headset_rounded : Icons.headset_off_rounded,
              color: _isBackgroundAudioEnabled ? AppColors.cyan : Colors.white70,
            ),
            tooltip: 'تشغيل الصوت في الخلفية',
            onPressed: _toggleBackgroundAudio,
          ),
          IconButton(
            icon: const Icon(Icons.picture_in_picture_alt_rounded, color: AppColors.cyan),
            tooltip: 'وضع صورة في صورة (PiP)',
            onPressed: _enterSystemPiP,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // مشغل الفيديو المباشر عالي الأداء والموثوقية
          Container(
            color: Colors.black,
            width: double.infinity,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: _isLoadingPlayer
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: AppColors.cyan, strokeWidth: 2.5),
                          SizedBox(height: 12),
                          Text(
                            'جاري التقاط رابط البث المباشر وتشغيله...',
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    )
                  : _playerError != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.error_outline_rounded, color: AppColors.orange, size: 40),
                                const SizedBox(height: 8),
                                Text(
                                  _playerError!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                                const SizedBox(height: 12),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.cyan,
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  onPressed: () => _initDirectStreamPlayer(_currentVideo),
                                  icon: const Icon(Icons.refresh_rounded, size: 16),
                                  label: const Text('إعادة المحاولة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _chewieController != null &&
                              _chewieController!.videoPlayerController.value.isInitialized
                          ? Chewie(controller: _chewieController!)
                          : const Center(
                              child: CircularProgressIndicator(color: AppColors.cyan),
                            ),
            ),
          ),

          // قائمة المعلومات وتنزيل الوسائط ومقاطع الفيديو المشابهة
          Expanded(
            child: ListView.builder(
              controller: _relatedScrollController,
              physics: const BouncingScrollPhysics(),
              itemCount: _relatedVideos.length + 2,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.all(18.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _currentVideo.title,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.person_outline, size: 16, color: AppColors.textMuted),
                            const SizedBox(width: 5),
                            Text(_currentVideo.author, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // زر استعراض الجودات والتحميل المباشر
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.cyan.withOpacity(0.25),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              )
                            ],
                          ),
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: _isLoadingExtraction ? null : _handleExtraction,
                            icon: _isLoadingExtraction
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                  )
                                : const Icon(Icons.download_rounded, color: Colors.white, size: 22),
                            label: Text(
                              _isLoadingExtraction ? 'جاري جلب خيارات التنزيل...' : 'استعراض الجودات والتنزيل',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                        ),
                        const SizedBox(height: 25),
                        const Text(
                          'فيديوهات ذات صلة',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                  );
                }

                if (index == _relatedVideos.length + 1) {
                  return _isLoadingMoreRelated
                      ? const Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(child: CircularProgressIndicator(color: AppColors.cyan)),
                        )
                      : const SizedBox(height: 50);
                }

                final relatedVideo = _relatedVideos[index - 1];
                return _buildRelatedVideoItem(relatedVideo);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRelatedVideoItem(yt.Video video) {
    return InkWell(
      onTap: () => _changeVideo(video),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    video.thumbnails.mediumResUrl,
                    width: 120,
                    height: 70,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 120,
                      height: 70,
                      color: AppColors.surfaceLight,
                      child: const Icon(Icons.video_library, color: AppColors.textMuted),
                    ),
                  ),
                ),
                if (video.duration != null)
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _formatDuration(video.duration!),
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    video.author,
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return '${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds';
    }
    return '$twoDigitMinutes:$twoDigitSeconds';
  }
}

/// نافذة استعراض الجودات مع زر تحميل واحد فقط يقوم بالتحميل في الخلفية دوماً
class FormatSelectionSheet extends StatefulWidget {
  final String title;
  final String highestAudioUrl;
  final int? highestAudioTag;
  final String? videoId;
  final List<Map<String, dynamic>> videoFormats;
  final List<Map<String, dynamic>> audioFormats;

  const FormatSelectionSheet({
    super.key,
    required this.title,
    required this.highestAudioUrl,
    this.highestAudioTag,
    this.videoId,
    required this.videoFormats,
    required this.audioFormats,
  });

  @override
  State<FormatSelectionSheet> createState() => _FormatSelectionSheetState();
}

class _FormatSelectionSheetState extends State<FormatSelectionSheet> {
  Map<String, dynamic>? _selectedFormat;

  @override
  void initState() {
    super.initState();
    // تحديد أول جودة متاحة تلقائياً لتسهيل تجربة المستخدم
    if (widget.videoFormats.isNotEmpty) {
      _selectedFormat = widget.videoFormats.first;
    } else if (widget.audioFormats.isNotEmpty) {
      _selectedFormat = widget.audioFormats.first;
    }
  }

  void _triggerDownload(Map<String, dynamic> format) {
    Navigator.pop(context);

    BackendService().startDownloadInBackground(
      selectedUrl: format['url'],
      title: widget.title,
      ext: format['ext'],
      needsMerge: format['needs_merge'] ?? false,
      highestAudioUrl: widget.highestAudioUrl,
      videoId: format['video_id'] ?? widget.videoId,
      videoTag: format['tag'],
      highestAudioTag: widget.highestAudioTag,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.downloading_rounded, color: AppColors.cyan),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'بدأ التحميل في الخلفية: ${widget.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.surface,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.72,
          decoration: BoxDecoration(
            color: AppColors.surface.withOpacity(0.95),
            border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
          ),
          child: DefaultTabController(
            length: 2,
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 6),
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
                const TabBar(
                  indicatorColor: AppColors.cyan,
                  labelColor: AppColors.cyan,
                  unselectedLabelColor: AppColors.textMuted,
                  tabs: [
                    Tab(icon: Icon(Icons.videocam_rounded, size: 20), text: 'فيديو'),
                    Tab(icon: Icon(Icons.music_note_rounded, size: 20), text: 'صوت MP3'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildList(widget.videoFormats),
                      _buildList(widget.audioFormats),
                    ],
                  ),
                ),
                // زر واحد فقط للتحميل في الخلفية دوماً
                if (_selectedFormat != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 25),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06))),
                    ),
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.cyan,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 4,
                      ),
                      onPressed: () => _triggerDownload(_selectedFormat!),
                      icon: const Icon(Icons.download_rounded, size: 20),
                      label: Text(
                        'تحميل (${_selectedFormat!['quality_name']})',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildList(List<Map<String, dynamic>> formats) {
    if (formats.isEmpty) return const Center(child: Text('غير متوفر', style: TextStyle(color: AppColors.textMuted)));

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      itemCount: formats.length,
      itemBuilder: (context, index) {
        final format = formats[index];
        final isSelected = _selectedFormat == format;
        final String? badge = format['quality_badge'];
        final String? desc = format['quality_desc'];

        return InkWell(
          onTap: () => setState(() => _selectedFormat = format),
          child: Container(
            color: isSelected ? AppColors.cyan.withOpacity(0.12) : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: isSelected ? AppColors.cyan : AppColors.textMuted,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            format['quality_name'],
                            style: TextStyle(
                              color: isSelected ? AppColors.cyan : AppColors.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          if (badge != null) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.cyan.withOpacity(0.2)
                                    : AppColors.surfaceLight,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                badge,
                                style: TextStyle(
                                  color: isSelected ? AppColors.cyan : AppColors.textSecondary,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (desc != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          desc,
                          style: TextStyle(
                            color: isSelected ? AppColors.cyan.withOpacity(0.85) : AppColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                      const SizedBox(height: 3),
                      Text(
                        '${format['size']} MB • ${format['ext'].toString().toUpperCase()}',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                // زر تحميل مباشر مصغر لكل جودة لتسهيل التحميل الفوري بنقرة واحدة
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isSelected ? AppColors.cyan : Colors.white10,
                    foregroundColor: isSelected ? Colors.black : Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _triggerDownload(format),
                  child: const Text('تحميل', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
