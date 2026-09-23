import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/app_colors.dart';
import '../../services/backend_service.dart';
import '../widgets/download_dialogs.dart';

class LinksTab extends StatefulWidget {
  const LinksTab({super.key});

  @override
  State<LinksTab> createState() => _LinksTabState();
}

class _LinksTabState extends State<LinksTab> with WidgetsBindingObserver {
  final TextEditingController _urlController = TextEditingController();
  final BackendService _backend = BackendService();

  bool _isAnalyzing = false;
  bool _hasResult = false;
  bool _isPlaylist = false;

  Map<String, dynamic>? _mediaData;
  Map<String, dynamic>? _playlistData;
  Map<String, dynamic>? _selectedFormat;
  String? _detectedClipboardUrl;

  // تحديد عناصر قائمة التشغيل
  final Set<int> _selectedPlaylistIndices = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkClipboardForMedia();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkClipboardForMedia();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _checkClipboardForMedia() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data != null && data.text != null) {
        final text = data.text!.trim();
        if ((text.startsWith('http://') || text.startsWith('https://')) && text.length > 10) {
          if (mounted) {
            setState(() {
              _detectedClipboardUrl = text;
            });
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _pasteFromClipboard() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    if (clipboardData != null && clipboardData.text != null) {
      setState(() {
        _urlController.text = clipboardData.text!.trim();
        _detectedClipboardUrl = null;
      });
    }
  }

  Future<void> _analyzeLink() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال الرابط أولاً')),
      );
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isAnalyzing = true;
      _hasResult = false;
      _isPlaylist = false;
      _selectedFormat = null;
      _selectedPlaylistIndices.clear();
    });

    try {
      // فحص إذا كان الرابط قائمة تشغيل
      if (_backend.isPlaylistUrl(url)) {
        final playlist = await _backend.extractPlaylist(url);
        final List videos = playlist['videos'] ?? [];
        if (mounted) {
          if (videos.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('قائمة التشغيل فارغة أو غير متاحة')),
            );
            setState(() => _isAnalyzing = false);
          } else {
            setState(() {
              _playlistData = playlist;
              _isPlaylist = true;
              _hasResult = true;
              _isAnalyzing = false;
              // تحديد جميع الفيديوهات افتراضياً
              _selectedPlaylistIndices.addAll(List.generate(videos.length, (i) => i));
            });
          }
        }
      } else {
        // فيديو فردي عادي
        final result = await _backend.extractMediaLinks(url);
        final List videoList = result['video'] ?? [];
        final List audioList = result['audio'] ?? [];

        if (mounted) {
          if (videoList.isEmpty && audioList.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(_backend.t('file_not_found'))),
            );
            setState(() => _isAnalyzing = false);
          } else {
            final processedVideos = _processFormats(List<Map<String, dynamic>>.from(videoList));
            final processedAudios = _processFormats(List<Map<String, dynamic>>.from(audioList));
            Map<String, dynamic>? initialFormat;
            if (processedVideos.isNotEmpty) {
              initialFormat = processedVideos.first; // أعلى جودة تلقائياً (1080p Full HD)
            } else if (processedAudios.isNotEmpty) {
              initialFormat = processedAudios.first;
            }

            setState(() {
              _mediaData = result;
              _isPlaylist = false;
              _hasResult = true;
              _isAnalyzing = false;
              _selectedFormat = initialFormat;
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isAnalyzing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
        );
      }
    }
  }

  void _showSchedulePicker() {
    if (_selectedFormat == null || _mediaData == null) return;
    final title = _mediaData?['title'] ?? 'فيديو بدون عنوان';
    final highestAudioUrl = _mediaData?['highestAudioUrl'] ?? '';

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(height: 18),
                const Row(
                  children: [
                    Icon(Icons.schedule_rounded, color: AppColors.cyan, size: 22),
                    SizedBox(width: 8),
                    Text(
                      'جدولة وقت التنزيل',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _buildScheduleTile(
                  title: 'بعد 30 دقيقة',
                  subtitle: 'مثالي للانتظار حتى الاتصال بالـ Wi-Fi',
                  minutes: 30,
                  titleVal: title,
                  audioUrl: highestAudioUrl,
                ),
                _buildScheduleTile(
                  title: 'بعد 1 ساعة',
                  subtitle: 'بدء التنزيل تلقائياً بعد ساعة',
                  minutes: 60,
                  titleVal: title,
                  audioUrl: highestAudioUrl,
                ),
                _buildScheduleTile(
                  title: 'بعد ساعتين (2 ساعات)',
                  subtitle: 'تنزيل في وقت لاحق',
                  minutes: 120,
                  titleVal: title,
                  audioUrl: highestAudioUrl,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildScheduleTile({
    required String title,
    required String subtitle,
    required int minutes,
    required String titleVal,
    required String audioUrl,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(10)),
        child: const Icon(Icons.timer_outlined, color: AppColors.cyan, size: 20),
      ),
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
      onTap: () {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تمت جدولة تنزيل: $titleVal بعد $minutes دقيقة ⏱️'),
            backgroundColor: AppColors.cyan,
          ),
        );

        Future.delayed(Duration(minutes: minutes), () {
          if (mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => DownloadProgressDialog(
                selectedUrl: _selectedFormat!['url'],
                title: titleVal,
                ext: _selectedFormat!['ext'],
                needsMerge: _selectedFormat!['needs_merge'],
                highestAudioUrl: audioUrl,
                videoId: _selectedFormat!['video_id'] ?? _mediaData?['id'],
                videoTag: _selectedFormat!['tag'],
                highestAudioTag: _mediaData?['highestAudioTag'],
              ),
            );
          }
        });
      },
    );
  }

  void _downloadBatch(bool isAudio) {
    if (_playlistData == null) return;
    final List allVideos = _playlistData!['videos'] ?? [];
    final selectedItems = _selectedPlaylistIndices
        .map((idx) => Map<String, dynamic>.from(allVideos[idx]))
        .toList();

    if (selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى تحديد مقطع واحد على الأقل للتحميل')),
      );
      return;
    }


    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => BatchDownloadProgressDialog(
        items: selectedItems,
        isAudio: isAudio,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 155),
        child: Column(
          children: [
            const SizedBox(height: 30),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.magenta.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.link, size: 50, color: AppColors.magenta),
            ),
            const SizedBox(height: 15),
            Text(
              _backend.t('have_link'),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 30),
            _buildInputSection(),
            const SizedBox(height: 30),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: _isAnalyzing
                  ? _buildLoadingState()
                  : _hasResult
                      ? (_isPlaylist ? _buildPlaylistCard() : _buildSingleResultCard())
                      : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          if (_detectedClipboardUrl != null) ...[
            GestureDetector(
              onTap: () {
                _urlController.text = _detectedClipboardUrl!;
                setState(() => _detectedClipboardUrl = null);
                _analyzeLink();
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.cyan.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.cyan.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome, color: AppColors.cyan, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _backend.t('clipboard_detected'),
                        style: const TextStyle(color: AppColors.cyan, fontSize: 12, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.cyan, size: 12),
                  ],
                ),
              ),
            ),
          ],
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: Column(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.background.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        controller: _urlController,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                        decoration: const InputDecoration(
                          hintText: 'ضع رابط أي فيديو (YouTube, TikTok, Insta, FB, X, أو أي موقع)...',
                          hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 13),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 15, vertical: 15),
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),
                    Row(
                      children: [
                        Expanded(
                          flex: 1,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.surface,
                              foregroundColor: AppColors.textPrimary,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: Colors.white.withOpacity(0.1)),
                              ),
                            ),
                            onPressed: _pasteFromClipboard,
                            icon: const Icon(Icons.content_paste, size: 18),
                            label: const Text('لصق', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: AppColors.primaryGradient,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.cyan.withOpacity(0.3),
                                  blurRadius: 10,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _analyzeLink,
                              child: Text(
                                _backend.t('download_btn'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          _buildQuickPlatforms(),
        ],
      ),
    );
  }

  Widget _buildQuickPlatforms() {
    final platforms = [
      {'name': 'YouTube', 'icon': Icons.smart_display_rounded, 'color': Colors.redAccent},
      {'name': 'TikTok', 'icon': Icons.music_note_rounded, 'color': AppColors.magenta},
      {'name': 'Instagram', 'icon': Icons.camera_alt_rounded, 'color': Colors.pinkAccent},
      {'name': 'Facebook', 'icon': Icons.facebook_rounded, 'color': Colors.blueAccent},
      {'name': 'X / Twitter', 'icon': Icons.tag_rounded, 'color': Colors.lightBlueAccent},
      {'name': 'Pinterest', 'icon': Icons.pin_drop_rounded, 'color': Colors.red},
      {'name': 'أي موقع ويب', 'icon': Icons.language_rounded, 'color': AppColors.cyan},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: platforms.map((p) {
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(p['icon'] as IconData, size: 14, color: p['color'] as Color),
                const SizedBox(width: 5),
                Text(
                  p['name'] as String,
                  style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Column(
      key: const ValueKey('loading'),
      children: [
        const CircularProgressIndicator(
          color: AppColors.cyan,
          strokeWidth: 3,
        ),
        const SizedBox(height: 15),
        Text(
          _backend.t('extracting'),
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        )
      ],
    );
  }

  // كرت قائمة التشغيل والتحميل الدفعي
  Widget _buildPlaylistCard() {
    final title = _playlistData?['title'] ?? 'قائمة تشغيل';
    final author = _playlistData?['author'] ?? 'قناة يوتيوب';
    final thumbnail = _playlistData?['thumbnail'] ?? '';
    final List videos = _playlistData?['videos'] ?? [];

    final isAllSelected = _selectedPlaylistIndices.length == videos.length;

    return Container(
      key: const ValueKey('playlist_result'),
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cyan.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (thumbnail.isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: Image.network(
                thumbnail,
                width: double.infinity,
                height: 160,
                fit: BoxFit.cover,
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.cyan.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('قائمة تشغيل يوتيوب', style: TextStyle(color: AppColors.cyan, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${videos.length} مقطع',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  author,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          const Divider(color: AppColors.surfaceLight, height: 1),

          // شريط تحديد الكل
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'المحدد: ${_selectedPlaylistIndices.length} من ${videos.length}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                ),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      if (isAllSelected) {
                        _selectedPlaylistIndices.clear();
                      } else {
                        _selectedPlaylistIndices.clear();
                        _selectedPlaylistIndices.addAll(List.generate(videos.length, (i) => i));
                      }
                    });
                  },
                  icon: Icon(isAllSelected ? Icons.deselect : Icons.select_all, size: 16, color: AppColors.cyan),
                  label: Text(
                    isAllSelected ? 'إلغاء التحديد' : 'تحديد الكل',
                    style: const TextStyle(color: AppColors.cyan, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),

          // قائمة الفيديوهات داخل قائمة التشغيل
          SizedBox(
            height: 240,
            child: ListView.builder(
              physics: const BouncingScrollPhysics(),
              itemCount: videos.length,
              itemBuilder: (ctx, i) {
                final v = videos[i];
                final isSelected = _selectedPlaylistIndices.contains(i);
                return CheckboxListTile(
                  value: isSelected,
                  activeColor: AppColors.cyan,
                  checkColor: Colors.black,
                  dense: true,
                  title: Text(
                    '${i + 1}. ${v['title']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white60,
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text(
                    '${v['duration'] ?? ''} • ${v['author'] ?? ''}',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                  ),
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        _selectedPlaylistIndices.add(i);
                      } else {
                        _selectedPlaylistIndices.remove(i);
                      }
                    });
                  },
                );
              },
            ),
          ),

          // أزرار التحميل الدفعي
          Padding(
            padding: const EdgeInsets.all(15),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.magenta,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => _downloadBatch(true),
                    icon: const Icon(Icons.music_note, color: Colors.white, size: 18),
                    label: const Text(
                      'تحميل الكل MP3',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.cyan,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => _downloadBatch(false),
                    icon: const Icon(Icons.movie, color: Colors.black, size: 18),
                    label: const Text(
                      'تحميل الكل MP4',
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // كرت الفيديو المفرد مع تبويبات (فيديو / صوت / ترجمات)
  Widget _buildSingleResultCard() {
    final title = _mediaData?['title'] ?? 'فيديو بدون عنوان';
    final thumbnail = _mediaData?['thumbnail'] ?? 'https://via.placeholder.com/400x225/12121A/00D9FF?text=Video';
    final highestAudioUrl = _mediaData?['highestAudioUrl'] ?? '';

    final videoList = _processFormats(List<Map<String, dynamic>>.from(_mediaData?['video'] ?? []));
    final audioList = _processFormats(List<Map<String, dynamic>>.from(_mediaData?['audio'] ?? []));
    final subtitlesList = List<Map<String, dynamic>>.from(_mediaData?['subtitles'] ?? []);

    return Container(
      key: const ValueKey('single_result'),
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: Image.network(
              thumbnail,
              width: double.infinity,
              height: 180,
              fit: BoxFit.cover,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(15),
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Divider(color: AppColors.surfaceLight, height: 1),
          DefaultTabController(
            length: 3,
            child: Column(
              children: [
                TabBar(
                  indicatorColor: AppColors.cyan,
                  labelColor: AppColors.cyan,
                  unselectedLabelColor: AppColors.textMuted,
                  tabs: [
                    Tab(icon: const Icon(Icons.video_library), text: _backend.t('video')),
                    Tab(icon: const Icon(Icons.library_music), text: _backend.t('audio')),
                    Tab(icon: const Icon(Icons.subtitles_rounded), text: _backend.t('subtitles')),
                  ],
                ),
                SizedBox(
                  height: 270,
                  child: TabBarView(
                    children: [
                      _buildFormatList(videoList, Icons.play_circle_outline),
                      _buildFormatList(audioList, Icons.music_note),
                      _buildSubtitlesList(subtitlesList, title),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_selectedFormat != null)
            Padding(
              padding: const EdgeInsets.all(15),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.blue.withOpacity(0.4),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                        onPressed: () {
                          _backend.startDownloadInBackground(
                            selectedUrl: _selectedFormat!['url'],
                            title: title,
                            ext: _selectedFormat!['ext'],
                            needsMerge: _selectedFormat!['needs_merge'] ?? false,
                            highestAudioUrl: highestAudioUrl,
                            videoId: _selectedFormat!['video_id'] ?? _mediaData?['id'],
                            videoTag: _selectedFormat!['tag'],
                            highestAudioTag: _mediaData?['highestAudioTag'],
                          );

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Row(
                                children: [
                                  const Icon(Icons.downloading_rounded, color: AppColors.cyan, size: 20),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'بدأ التحميل في الخلفية: $title',
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
                        },
                        icon: const Icon(Icons.download_rounded, color: Colors.white),
                        label: const Text(
                          'تحميل',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // زر جدولة التحميل
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.schedule_rounded, color: AppColors.cyan, size: 24),
                      onPressed: _showSchedulePicker,
                      tooltip: 'جدولة التنزيل',
                      padding: const EdgeInsets.all(14),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // قائمة الترجمات المتاحة
  Widget _buildSubtitlesList(List<Map<String, dynamic>> subtitles, String videoTitle) {
    if (subtitles.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.subtitles_off_rounded, color: AppColors.textMuted, size: 36),
            SizedBox(height: 8),
            Text('لا توجد ملفات ترجمة متوفرة لهذا المقطع', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ],
        ),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 10),
      itemCount: subtitles.length,
      itemBuilder: (ctx, idx) {
        final sub = subtitles[idx];
        final name = sub['name'] ?? 'لغة غير معروفة';
        final code = sub['code'] ?? '';
        final isAuto = sub['isAuto'] ?? false;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.closed_caption_rounded, color: AppColors.cyan, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    Text(
                      '${code.toString().toUpperCase()} ${isAuto ? '• ترجمة تلقائية' : '• ترجمة رسمية'}',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.cyan.withOpacity(0.2),
                  foregroundColor: AppColors.cyan,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () async {
                  try {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('جاري تحميل ملف الترجمة SRT...')),
                    );
                    final path = await _backend.downloadSubtitleTrack(
                      track: sub['track'],
                      videoTitle: videoTitle,
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('تم تحميل ملف الترجمة بنجاح: ${path.split('/').last} 📄'),
                          backgroundColor: AppColors.cyan,
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('فشل تحميل الترجمة: $e'), backgroundColor: AppColors.orange),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.download_rounded, size: 16),
                label: const Text('SRT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      },
    );
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
        // نفضل دائماً صيغة MP4 (H.264) لتفادي أي مشاكل ترميز، ثم الدفق الجاهز مسبقاً
        if (existing['container'] != 'mp4' && f['container'] == 'mp4') {
          uniqueFormats[key] = f;
        } else if (existing['needs_merge'] == true && f['needs_merge'] == false && (existing['container'] == f['container'])) {
          uniqueFormats[key] = f;
        }
      }
    }
    var sortedList = uniqueFormats.values.toList();

    // ترتيب القائمة تنازلياً من أعلى جودة (1080p Full HD أو أعلى) إلى أدنى جودة
    sortedList.sort((a, b) {
      int orderA = a['quality_order'] is int 
          ? a['quality_order'] 
          : (int.tryParse(a['quality_order']?.toString() ?? '') ?? 0);
      int orderB = b['quality_order'] is int 
          ? b['quality_order'] 
          : (int.tryParse(b['quality_order']?.toString() ?? '') ?? 0);
      
      if (orderA != 0 && orderB != 0 && orderA != orderB) {
        return orderB.compareTo(orderA); // أعلى جودة أولاً
      }
      double sizeA = double.tryParse(a['size'].toString()) ?? 0.0;
      double sizeB = double.tryParse(b['size'].toString()) ?? 0.0;
      return sizeB.compareTo(sizeA); // الأكبر حجماً أولاً
    });
    return sortedList;
  }

  Widget _buildFormatList(List<Map<String, dynamic>> formats, IconData icon) {
    if (formats.isEmpty) {
      return const Center(
        child: Text('هذه الصيغة غير متوفرة', style: TextStyle(color: AppColors.textMuted)),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 10),
      itemCount: formats.length,
      itemBuilder: (context, index) {
        final format = formats[index];
        final isSelected = _selectedFormat == format;
        final String? badge = format['quality_badge'];
        final String? desc = format['quality_desc'];
        final int order = format['quality_order'] is int 
            ? format['quality_order'] 
            : (int.tryParse(format['quality_order']?.toString() ?? '') ?? 0);
        final bool isHighDef = order >= 1080;

        return InkWell(
          onTap: () {
            setState(() {
              _selectedFormat = format;
            });
          },
          child: Container(
            color: isSelected 
                ? AppColors.cyan.withOpacity(0.12) 
                : (isHighDef ? Colors.white.withOpacity(0.02) : Colors.transparent),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: isSelected ? AppColors.cyan : (isHighDef ? AppColors.cyan.withOpacity(0.7) : AppColors.textMuted),
                    size: 20,
                  ),
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
                              color: isSelected 
                                  ? AppColors.cyan 
                                  : (isHighDef ? Colors.white : AppColors.textPrimary),
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          if (badge != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isSelected 
                                    ? AppColors.cyan.withOpacity(0.2) 
                                    : (isHighDef ? AppColors.cyan.withOpacity(0.15) : AppColors.surfaceLight),
                                borderRadius: BorderRadius.circular(4),
                                border: isHighDef ? Border.all(color: AppColors.cyan.withOpacity(0.4), width: 0.8) : null,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isHighDef) ...[
                                    const Icon(Icons.star_rounded, color: AppColors.cyan, size: 11),
                                    const SizedBox(width: 2),
                                  ],
                                  Text(
                                    badge,
                                    style: TextStyle(
                                      color: isSelected || isHighDef ? AppColors.cyan : AppColors.textSecondary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (desc != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          desc,
                          style: TextStyle(
                            color: isSelected ? AppColors.cyan.withOpacity(0.85) : AppColors.textMuted,
                            fontSize: 11,
                            height: 1.3,
                          ),
                        ),
                      ],
                      const SizedBox(height: 3),
                      Text(
                        'الحجم: ${format['size']} MB',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        format['ext'].toString().toUpperCase(),
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (format['needs_merge'] == true) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.orange.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('دقة أصلية', style: TextStyle(color: AppColors.orange, fontSize: 9)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
