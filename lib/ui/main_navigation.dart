import 'dart:ui';
import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../services/backend_service.dart';
import 'tabs/youtube_tab.dart';
import 'tabs/links_tab.dart';
import 'tabs/downloads_tab.dart';
import 'tabs/settings_tab.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  final BackendService _backend = BackendService();
  int _currentIndex = 0;
  static const MethodChannel _shareChannel = MethodChannel('com.boykta.app/share_intent');

  final List<Widget> _tabs = const [
    YoutubeTab(),
    LinksTab(),
    DownloadsTab(),
    SettingsTab(),
  ];

  @override
  void initState() {
    super.initState();
    _initShareIntentListener();
  }

  void _initShareIntentListener() async {
    _shareChannel.setMethodCallHandler((call) async {
      if (call.method == 'onLinkReceived') {
        final text = call.arguments?.toString();
        if (text != null && text.isNotEmpty) {
          _handleIncomingSharedText(text);
        }
      }
    });

    try {
      final initial = await _shareChannel.invokeMethod<String>('getInitialSharedText');
      if (initial != null && initial.isNotEmpty) {
        _handleIncomingSharedText(initial);
      }
    } catch (_) {}
  }

  void _handleIncomingSharedText(String text) {
    final url = _backend.extractFirstUrl(text);
    if (url != null && url.isNotEmpty) {
      _backend.pendingSharedUrl.value = url;
      if (mounted) {
        setState(() {
          _currentIndex = 1; // الانتقال الفوري لتبويب الروابط
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: ValueListenableBuilder<String>(
        valueListenable: _backend.langNotifier,
        builder: (context, lang, child) {
          return IndexedStack(
            index: _currentIndex,
            children: _tabs,
          );
        },
      ),
      bottomNavigationBar: ValueListenableBuilder<String>(
        valueListenable: _backend.langNotifier,
        builder: (context, lang, child) {
          return Container(
            margin: const EdgeInsets.only(left: 14, right: 14, bottom: 18),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(25),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  height: 68,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(25),
                    border: Border.all(color: Colors.white.withOpacity(0.06)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildNavItem(Icons.play_circle_fill, _backend.t('youtube'), 0),
                      _buildNavItem(Icons.link_rounded, _backend.t('link'), 1),
                      _buildNavItem(Icons.download_rounded, _backend.t('downloads'), 2),
                      _buildNavItem(Icons.settings_rounded, _backend.t('settings'), 3),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    bool isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.cyan.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  icon,
                  color: isSelected ? AppColors.cyan : AppColors.textMuted,
                  size: isSelected ? 24 : 22,
                ),
                if (index == 2)
                  ValueListenableBuilder<List<DownloadTask>>(
                    valueListenable: _backend.activeDownloads,
                    builder: (context, tasks, child) {
                      if (tasks.isEmpty) return const SizedBox.shrink();
                      return Positioned(
                        top: -2,
                        right: -4,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: AppColors.cyan,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.cyan.withOpacity(0.8),
                                blurRadius: 4,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
            if (isSelected) ...[
              const SizedBox(height: 3),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.cyan,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}
