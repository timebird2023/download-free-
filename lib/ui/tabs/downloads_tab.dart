import 'dart:io';
import 'dart:ui';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/app_colors.dart';
import '../../services/backend_service.dart';
import '../../services/biometric_service.dart';
import '../local_video_player_screen.dart'; 
import '../vault_screen.dart';
import '../audio_trimmer_screen.dart';
import '../calculator_vault_screen.dart';
import '../web_share_screen.dart'; 

class DownloadsTab extends StatefulWidget {
  const DownloadsTab({super.key});

  @override
  State<DownloadsTab> createState() => _DownloadsTabState();
}

class _DownloadsTabState extends State<DownloadsTab> with SingleTickerProviderStateMixin {
  final BackendService _backend = BackendService();
  late TabController _tabController;
  List<FileSystemEntity> _videoFiles = [];
  List<FileSystemEntity> _audioFiles = [];
  bool _isLoading = true;

  late AudioPlayer _audioPlayer;
  File? _currentAudio;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initAudioPlayer();
    _loadFiles();
    _backend.activeDownloads.addListener(_onActiveDownloadsChanged);
  }

  void _initAudioPlayer() {
    _audioPlayer = AudioPlayer();
    
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _isPlaying = state == PlayerState.playing);
    });

    _audioPlayer.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });

    _audioPlayer.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });

    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
        });
      }
    });
  }

  void _onActiveDownloadsChanged() {
    if (_backend.activeDownloads.value.isEmpty) {
      _loadFiles(); 
    }
  }

  bool _isAudioFile(String path) {
    final p = path.toLowerCase();
    return p.endsWith('.mp3') ||
           p.endsWith('.m4a') ||
           p.endsWith('.opus') ||
           p.endsWith('.wav') ||
           p.endsWith('.aac') ||
           p.endsWith('.ogg');
  }

  Future<void> _loadFiles() async {
    setState(() => _isLoading = true);
    final files = await _backend.getDownloadedFiles();
    
    if (mounted) {
      setState(() {
        _videoFiles = files.where((f) => !_isAudioFile(f.path)).toList();
        _audioFiles = files.where((f) => _isAudioFile(f.path)).toList();
        _isLoading = false;
      });
    }
  }

  void _playAudio(File file) async {
    if (_currentAudio?.path == file.path) {
      if (_isPlaying) {
        await _audioPlayer.pause();
      } else {
        await _audioPlayer.resume();
      }
    } else {
      await _audioPlayer.play(DeviceFileSource(file.path));
      setState(() => _currentAudio = file);
    }
  }

  void _openVault() async {
    final isDisguise = await _backend.isCalculatorDisguiseEnabled();
    if (isDisguise && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CalculatorVaultScreen()),
      ).then((_) => _loadFiles());
      return;
    }

    final bioService = BiometricService();
    if (await bioService.isBiometricEnabled() && await bioService.isBiometricSupported()) {
      final authenticated = await bioService.authenticate();
      if (authenticated && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const VaultScreen()),
        ).then((_) => _loadFiles());
        return;
      }
    }

    final hasPin = await _backend.isVaultPinSet();
    if (!mounted) return;
    if (!hasPin) {
      _showSetVaultPinDialog();
    } else {
      _showEnterVaultPinDialog();
    }
  }

  void _showSetVaultPinDialog() {
    final pinCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.shield_rounded, color: AppColors.cyan, size: 24),
            const SizedBox(width: 8),
            Text(_backend.t('set_pin'), style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_backend.t('vault_desc'), style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 16),
            TextField(
              controller: pinCtrl,
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
              style: const TextStyle(color: Colors.white, letterSpacing: 8, fontSize: 20),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: '••••',
                hintStyle: const TextStyle(color: Colors.white38, letterSpacing: 8),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.cyan),
            onPressed: () async {
              if (pinCtrl.text.trim().length == 4) {
                await _backend.setVaultPin(pinCtrl.text.trim());
                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(_backend.t('pin_set_success')), backgroundColor: AppColors.cyan.withOpacity(0.9)),
                  );
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const VaultScreen())).then((_) => _loadFiles());
                }
              }
            },
            child: const Text('حفظ والدخول', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showEnterVaultPinDialog() {
    final pinCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.lock_rounded, color: AppColors.cyan, size: 24),
            const SizedBox(width: 8),
            Text(_backend.t('enter_pin'), style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pinCtrl,
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
              style: const TextStyle(color: Colors.white, letterSpacing: 8, fontSize: 20),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: '••••',
                hintStyle: const TextStyle(color: Colors.white38, letterSpacing: 8),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.cyan),
            onPressed: () async {
              final isCorrect = await _backend.verifyVaultPin(pinCtrl.text.trim());
              if (isCorrect) {
                if (mounted) {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const VaultScreen())).then((_) => _loadFiles());
                }
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(_backend.t('wrong_pin')), backgroundColor: AppColors.orange),
                  );
                }
              }
            },
            child: const Text('دخول', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _lockFileInVault(File file) async {
    final hasPin = await _backend.isVaultPinSet();
    if (!hasPin) {
      _showSetVaultPinDialog();
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            const Icon(Icons.shield_rounded, color: AppColors.cyan, size: 22),
            const SizedBox(width: 8),
            Text(_backend.t('move_to_vault'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'هل تريد نقل هذا الملف إلى الخزنة الآمنة المحمية برمز PIN؟',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.cyan),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('نقل وقفل', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await _backend.moveToVault(file);
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_backend.t('moved_to_vault_success')), backgroundColor: AppColors.cyan.withOpacity(0.9)),
          );
          _loadFiles();
        }
      }
    }
  }

  @override
  void dispose() {
    _backend.activeDownloads.removeListener(_onActiveDownloadsChanged);
    _audioPlayer.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // الهيدر الرئيسي
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 15, 20, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _backend.t('downloads'), 
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary)
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.wifi_tethering_rounded, color: AppColors.cyan),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const WebShareScreen()),
                            );
                          },
                          tooltip: 'مشاركة عبر الـ Wi-Fi للكمبيوتر',
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded, color: AppColors.cyan),
                          onPressed: _loadFiles,
                          tooltip: 'تحديث',
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // كرت الخزنة الآمنة المميز والواضح
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: InkWell(
                  onTap: _openVault,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.cyan.withOpacity(0.18),
                          AppColors.magenta.withOpacity(0.12),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.cyan.withOpacity(0.35)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.cyan.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.shield_rounded, color: AppColors.cyan, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _backend.t('vault'),
                                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _backend.t('vault_desc'),
                                style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.cyan,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.lock_rounded, size: 14, color: Colors.black),
                              SizedBox(width: 4),
                              Text('دخول', style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              
              // قائمة التنزيلات الجارية حالياً
              ValueListenableBuilder<List<DownloadTask>>(
                valueListenable: _backend.activeDownloads,
                builder: (context, tasks, child) {
                  if (tasks.isEmpty) return const SizedBox.shrink();
                  return Column(
                    children: tasks.map((t) {
                      final bool isFailed = t.isFailed;
                      final double prog = t.progress;
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isFailed 
                              ? Colors.red.withOpacity(0.12)
                              : AppColors.surfaceLight.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isFailed ? Colors.redAccent : AppColors.cyan.withOpacity(0.5),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: (isFailed ? Colors.red : AppColors.cyan).withOpacity(0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: (isFailed ? Colors.red : AppColors.cyan).withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    isFailed 
                                        ? Icons.error_outline_rounded 
                                        : (t.isAudio ? Icons.music_note_rounded : Icons.video_collection_rounded),
                                    color: isFailed ? Colors.redAccent : AppColors.cyan,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        t.title,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        t.status,
                                        style: TextStyle(
                                          color: isFailed ? Colors.redAccent : AppColors.cyan,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                if (t.speed.isNotEmpty && !isFailed)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      t.speed,
                                      style: const TextStyle(
                                        color: Colors.greenAccent,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: LinearProgressIndicator(
                                value: (prog > 0.0 && prog <= 1.0) ? prog : null,
                                backgroundColor: Colors.white12,
                                color: isFailed ? Colors.redAccent : AppColors.cyan,
                                minHeight: 10,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  prog > 0 ? "${(prog * 100).toStringAsFixed(1)}%" : "جاري التجهيز...",
                                  style: TextStyle(
                                    color: isFailed ? Colors.redAccent : AppColors.cyan,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  t.total != "--" && t.total != "0.0"
                                      ? "${t.downloaded} MB / ${t.total} MB"
                                      : "${t.downloaded} MB",
                                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
              // تبويبات الفيديو والصوت
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    color: AppColors.cyan,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  labelColor: Colors.black,
                  unselectedLabelColor: AppColors.textMuted,
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                  tabs: [
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.video_library, size: 18),
                          const SizedBox(width: 8),
                          Text('${_backend.t('video')} (${_videoFiles.length})'),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.library_music, size: 18),
                          const SizedBox(width: 8),
                          Text('${_backend.t('audio')} (${_audioFiles.length})'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: _isLoading 
                  ? const Center(child: CircularProgressIndicator(color: AppColors.cyan))
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildFilesList(_videoFiles, isAudio: false),
                        _buildFilesList(_audioFiles, isAudio: true),
                      ],
                    ),
              )
            ],
          ),

          // مشغل الصوت المصغر
          if (_currentAudio != null)
            Positioned(
              left: 15,
              right: 15,
              bottom: 100, 
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.cyan.withOpacity(0.3)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.magenta.withOpacity(0.2),
                                shape: BoxShape.circle
                              ),
                              child: const Icon(Icons.music_note, color: AppColors.magenta, size: 20),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _currentAudio!.path.split('/').last, 
                                maxLines: 1, 
                                overflow: TextOverflow.ellipsis, 
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)
                              )
                            ),
                            IconButton(
                              icon: Icon(
                                _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill, 
                                color: AppColors.cyan, 
                                size: 36
                              ),
                              onPressed: () => _playAudio(_currentAudio!),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 24),
                              onPressed: () {
                                _audioPlayer.stop();
                                setState(() => _currentAudio = null);
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        SizedBox(
                          height: 20,
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                              trackHeight: 3,
                            ),
                            child: Slider(
                              activeColor: AppColors.magenta,
                              inactiveColor: Colors.white24,
                              value: _position.inSeconds.toDouble().clamp(0.0, _duration.inSeconds.toDouble()),
                              max: _duration.inSeconds.toDouble() > 0 ? _duration.inSeconds.toDouble() : 1.0,
                              onChanged: (val) => _audioPlayer.seek(Duration(seconds: val.toInt())),
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
      ),
    );
  }

  Widget _buildFilesList(List<FileSystemEntity> files, {required bool isAudio}) {
    if (files.isEmpty) return _buildEmptyState(isAudio);

    return RefreshIndicator(
      color: AppColors.cyan,
      backgroundColor: AppColors.surface,
      onRefresh: _loadFiles,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: EdgeInsets.only(bottom: _currentAudio != null ? 220 : 160, top: 10), 
        itemCount: files.length,
        itemBuilder: (context, index) {
          final file = files[index] as File;
          return _buildDownloadCard(file, isAudio, index);
        },
      ),
    );
  }

  Widget _buildDownloadCard(File file, bool isAudio, int index) {
    final fileName = file.path.split('/').last;
    final isCurrentlyPlaying = _currentAudio?.path == file.path;

    String sizeStr = '';
    try {
      if (file.existsSync()) {
        final bytes = file.lengthSync();
        if (bytes >= 1024 * 1024) {
          sizeStr = '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
        } else {
          sizeStr = '${(bytes / 1024).toStringAsFixed(1)} KB';
        }
      }
    } catch (_) {}

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isCurrentlyPlaying ? AppColors.magenta.withOpacity(0.15) : AppColors.surfaceLight.withOpacity(0.5),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: isCurrentlyPlaying ? AppColors.magenta.withOpacity(0.6) : Colors.white.withOpacity(0.05)
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 75,
                  height: 55,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: _buildThumbnail(file, isAudio, isCurrentlyPlaying),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fileName, 
                        maxLines: 2, 
                        overflow: TextOverflow.ellipsis, 
                        style: TextStyle(
                          color: isCurrentlyPlaying ? AppColors.magenta : AppColors.textPrimary, 
                          fontWeight: FontWeight.bold, 
                          fontSize: 13
                        )
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (sizeStr.isNotEmpty)
                            Text(
                              sizeStr,
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isAudio ? AppColors.magenta.withOpacity(0.2) : AppColors.cyan.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isAudio ? 'صوت' : 'فيديو',
                              style: TextStyle(
                                color: isAudio ? AppColors.magenta : AppColors.cyan,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                // زر التشغيل السريع
                IconButton(
                  icon: Icon(
                    isAudio 
                      ? (isCurrentlyPlaying && _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill) 
                      : Icons.play_circle_fill, 
                    color: isAudio && isCurrentlyPlaying ? AppColors.magenta : AppColors.cyan, 
                    size: 32
                  ),
                  onPressed: () {
                    if (file.existsSync()) {
                      if (isAudio) {
                        _playAudio(file);
                      } else {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => LocalVideoPlayerScreen(file: file)));
                      }
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_backend.t('file_not_found'))));
                      _loadFiles();
                    }
                  },
                ),

                // قائمة الخيارات الإضافية (تحويل MP3، قفل بالخزنة، مشاركة، حذف) بدون أي Overflow
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, color: Colors.white70, size: 22),
                  color: AppColors.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  onSelected: (val) {
                    if (val == 'convert') {
                      _convertVideo(file);
                    } else if (val == 'trim') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => AudioTrimmerScreen(file: file)),
                      ).then((_) => _loadFiles());
                    } else if (val == 'vault') {
                      _lockFileInVault(file);
                    } else if (val == 'share') {
                      Share.shareXFiles([XFile(file.path)], text: fileName);
                    } else if (val == 'delete') {
                      _deleteFile(file.path, file, isAudio);
                    }
                  },
                  itemBuilder: (context) => [
                    if (!isAudio)
                      PopupMenuItem(
                        value: 'convert',
                        child: Row(
                          children: [
                            const Icon(Icons.audiotrack_rounded, color: AppColors.magenta, size: 20),
                            const SizedBox(width: 10),
                            Text(_backend.t('convert_to_mp3'), style: const TextStyle(color: Colors.white, fontSize: 13)),
                          ],
                        ),
                      ),
                    PopupMenuItem(
                      value: 'trim',
                      child: const Row(
                        children: [
                          Icon(Icons.content_cut_rounded, color: AppColors.magenta, size: 20),
                          SizedBox(width: 10),
                          Text('قص وتعديل الصوت (صانع النغمات)', style: TextStyle(color: Colors.white, fontSize: 13)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'vault',
                      child: Row(
                        children: [
                          const Icon(Icons.shield_rounded, color: AppColors.cyan, size: 20),
                          const SizedBox(width: 10),
                          Text(_backend.t('move_to_vault'), style: const TextStyle(color: Colors.white, fontSize: 13)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'share',
                      child: Row(
                        children: [
                          const Icon(Icons.share_rounded, color: Colors.white70, size: 20),
                          const SizedBox(width: 10),
                          Text(_backend.t('share'), style: const TextStyle(color: Colors.white, fontSize: 13)),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(height: 1),
                    PopupMenuItem(
                      value: 'delete',
                      child: const Row(
                        children: [
                          Icon(Icons.delete_outline_rounded, color: AppColors.orange, size: 20),
                          SizedBox(width: 10),
                          Text('حذف', style: TextStyle(color: AppColors.orange, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail(File file, bool isAudio, bool isPlaying) {
    if (isAudio) {
      return Container(
        color: AppColors.magenta.withOpacity(0.2), 
        child: Icon(
          isPlaying ? Icons.graphic_eq_rounded : Icons.music_note_rounded, 
          color: AppColors.magenta, 
          size: 30
        )
      );
    }
    
    return FutureBuilder<Uint8List?>(
      future: VideoThumbnail.thumbnailData(
        video: file.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 150,
        quality: 50,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done && snapshot.data != null) {
          return Image.memory(
            snapshot.data!,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(
              color: AppColors.surfaceLight,
              child: const Icon(Icons.videocam, color: AppColors.cyan, size: 30),
            ),
          );
        }
        return Container(
          color: AppColors.surfaceLight,
          child: const Icon(Icons.videocam, color: AppColors.cyan, size: 30),
        );
      },
    );
  }

  Future<void> _deleteFile(String path, File file, bool isAudio) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('تأكيد الحذف', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text('هل أنت متأكد من رغبتك في حذف هذا الملف نهائياً؟', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.orange),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        if (file.existsSync()) {
          file.deleteSync();
        }
        setState(() {
          if (isAudio) {
            _audioFiles.removeWhere((f) => f.path == path);
            if (_currentAudio?.path == path) {
              _audioPlayer.stop();
              _currentAudio = null;
            }
          } else {
            _videoFiles.removeWhere((f) => f.path == path);
          }
        });
      } catch (e) {
        debugPrint('Delete error: $e');
      }
    }
  }

  Future<void> _convertVideo(File file) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_backend.t('converting')),
        duration: const Duration(seconds: 2),
      ),
    );

    bool success = await _backend.convertVideoToMp3(
      videoFile: file,
      onStatus: (status) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(status),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
    );

    if (success && mounted) {
      _loadFiles();
    }
  }

  Widget _buildEmptyState(bool isAudio) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isAudio ? AppColors.magenta.withOpacity(0.1) : AppColors.cyan.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isAudio ? Icons.music_off_rounded : Icons.videocam_off_rounded, 
              size: 60, 
              color: isAudio ? AppColors.magenta : AppColors.cyan
            ),
          ),
          const SizedBox(height: 15),
          Text(
            isAudio ? _backend.t('no_audio') : _backend.t('no_video'), 
            style: const TextStyle(color: AppColors.textMuted, fontSize: 16)
          ),
          const SizedBox(height: 8),
          const Text(
            'حمّل مقاطع جديدة من تبويب يوتيوب أو الروابط لتظهر هنا',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
