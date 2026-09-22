import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../core/app_colors.dart';
import '../../services/backend_service.dart';

class BrowserTab extends StatefulWidget {
  const BrowserTab({super.key});

  @override
  State<BrowserTab> createState() => _BrowserTabState();
}

class _BrowserTabState extends State<BrowserTab> {
  final BackendService _backend = BackendService();
  final TextEditingController _urlController = TextEditingController();

  late final WebViewController _controller;
  bool _isLoading = false;
  double _progress = 0.0;
  String _currentUrl = 'https://www.google.com';
  String _currentTitle = 'Google';
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _isDesktopMode = false;
  bool _hasEnteredSite = false;

  // ==========================================
  // مانع الإعلانات الذكي (AdBlocker)
  // ==========================================
  bool _adBlockerEnabled = true;
  int _blockedAdsCount = 0;
  static const List<String> _adFilterDomains = [
    'doubleclick.net',
    'googlesyndication.com',
    'adservice.google.com',
    'googleads.g.doubleclick.net',
    'popads.net',
    'adroll.com',
    'adnxs.com',
    'scorecardresearch.com',
    'criteo.com',
    'taboola.com',
    'outbrain.com',
    'propellerads.com',
    'bidswitch.net',
    'smartadserver.com',
    'rubiconproject.com',
    'moatads.com',
    'adcolony.com',
    'applovin.com',
    'unityads.unity3d.com',
    'inmobi.com',
    'vungle.com',
    'pubmatic.com',
    'openx.net',
    'advertising.com',
    'revcontent.com',
    'mgid.com',
    'adsterra.com',
    'adcash.com',
    'popcash.net',
    'exoclick.com',
    'monetag.com',
    'hilltopads.net',
    'clickadu.com',
    'richpush.co',
    'trafficjunky.net',
    'adform.net',
    'serving-sys.com',
    'yadro.ru',
    'exoclick.com',
    'trafficjunky.com',
  ];

  // ==========================================
  // إدارة الإشارات المرجعية (Bookmarks)
  // ==========================================
  List<Map<String, String>> _bookmarks = [];
  bool _isCurrentBookmarked = false;

  // ==========================================
  // وضع التصفح الخفي (Incognito Mode)
  // ==========================================
  bool _isIncognitoMode = false;

  // ==========================================
  // اختيار محرك البحث المفضل
  // ==========================================
  String _selectedSearchEngine = 'Google';
  final Map<String, String> _searchEngines = {
    'Google': 'https://www.google.com/search?q=',
    'DuckDuckGo': 'https://duckduckgo.com/?q=',
    'Bing': 'https://www.bing.com/search?q=',
    'Yahoo': 'https://search.yahoo.com/search?p=',
    'Yandex': 'https://yandex.com/search/?text=',
  };

  final List<Map<String, dynamic>> _quickShortcuts = [
    {'name': 'Google', 'url': 'https://www.google.com', 'icon': Icons.search_rounded, 'color': AppColors.cyan},
    {'name': 'YouTube', 'url': 'https://www.youtube.com', 'icon': Icons.smart_display_rounded, 'color': Colors.redAccent},
    {'name': 'TikTok', 'url': 'https://www.tiktok.com', 'icon': Icons.music_note_rounded, 'color': AppColors.cyan},
    {'name': 'Instagram', 'url': 'https://www.instagram.com', 'icon': Icons.camera_alt_rounded, 'color': Colors.pinkAccent},
    {'name': 'Facebook', 'url': 'https://www.facebook.com', 'icon': Icons.facebook_rounded, 'color': Colors.blueAccent},
    {'name': 'SoundCloud', 'url': 'https://soundcloud.com', 'icon': Icons.cloud_rounded, 'color': Colors.orangeAccent},
    {'name': 'Twitter / X', 'url': 'https://x.com', 'icon': Icons.tag_rounded, 'color': Colors.white},
    {'name': 'Wikipedia', 'url': 'https://ar.wikipedia.org', 'icon': Icons.menu_book_rounded, 'color': Colors.tealAccent},
  ];

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _initWebView();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    
    // تحميل مانع الإعلانات
    _adBlockerEnabled = prefs.getBool('browser_adblock_enabled') ?? true;
    _blockedAdsCount = prefs.getInt('browser_adblock_count') ?? 0;

    // تحميل محرك البحث المفضل
    _selectedSearchEngine = prefs.getString('browser_search_engine') ?? 'Google';
    if (!_searchEngines.containsKey(_selectedSearchEngine)) {
      _selectedSearchEngine = 'Google';
    }

    // تحميل الإشارات المرجعية
    final bStr = prefs.getString('browser_bookmarks');
    if (bStr != null && bStr.isNotEmpty) {
      try {
        final List decoded = jsonDecode(bStr);
        _bookmarks = decoded.map((e) => Map<String, String>.from(e)).toList();
      } catch (_) {}
    }

    if (mounted) setState(() {});
  }

  Future<void> _saveBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('browser_bookmarks', jsonEncode(_bookmarks));
    _checkBookmarkStatus();
  }

  void _checkBookmarkStatus() {
    final exists = _bookmarks.any((b) => b['url'] == _currentUrl);
    if (mounted && exists != _isCurrentBookmarked) {
      setState(() => _isCurrentBookmarked = exists);
    }
  }

  void _toggleBookmark() async {
    if (_isCurrentBookmarked) {
      _bookmarks.removeWhere((b) => b['url'] == _currentUrl);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تمت إزالة الصفحة من الإشارات المرجعية 🗑️'), duration: Duration(seconds: 1)),
      );
    } else {
      _bookmarks.add({
        'title': _currentTitle.isNotEmpty ? _currentTitle : _currentUrl,
        'url': _currentUrl,
        'date': DateTime.now().toIso8601String(),
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تمت إضافة الصفحة للإشارات المرجعية ⭐'), duration: Duration(seconds: 1)),
      );
    }
    await _saveBookmarks();
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            final url = request.url.toLowerCase();

            // فحص مانع الإعلانات
            if (_adBlockerEnabled) {
              for (final domain in _adFilterDomains) {
                if (url.contains(domain)) {
                  setState(() => _blockedAdsCount++);
                  _incrementBlockedCount();
                  debugPrint('🛡️ تم حظر إعلان: ${request.url}');
                  return NavigationDecision.prevent;
                }
              }
            }

            return NavigationDecision.navigate;
          },
          onProgress: (int progress) {
            if (mounted) {
              setState(() {
                _progress = progress / 100;
              });
            }
          },
          onPageStarted: (String url) {
            if (mounted) {
              final isSite = url.isNotEmpty && url != 'about:blank';
              setState(() {
                _isLoading = true;
                _currentUrl = url;
                _urlController.text = url;
                if (isSite) {
                  _hasEnteredSite = true;
                  _backend.isBrowserExpanded.value = true;
                }
              });
            }
          },
          onPageFinished: (String url) async {
            final canBack = await _controller.canGoBack();
            final canFwd = await _controller.canGoForward();
            final title = await _controller.getTitle() ?? url;

            if (mounted) {
              setState(() {
                _isLoading = false;
                _canGoBack = canBack;
                _canGoForward = canFwd;
                _currentUrl = url;
                _currentTitle = title;
                if (url.isNotEmpty && url != 'about:blank') {
                  _hasEnteredSite = true;
                  _backend.isBrowserExpanded.value = true;
                }
              });
              _checkBookmarkStatus();
              if (_adBlockerEnabled) {
                _injectAdCleanerScript();
              }
            }
          },
          onWebResourceError: (WebResourceError error) {
            if (mounted) {
              setState(() => _isLoading = false);
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(_currentUrl));
  }

  Future<void> _incrementBlockedCount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('browser_adblock_count', _blockedAdsCount);
  }

  // حقن سكربت تنظيف الإعلانات من الصفحة
  void _injectAdCleanerScript() {
    const jsClean = '''
      (function() {
        try {
          var sel = '.adsbygoogle, [id*="ad-"], [class*="ad-box"], [class*="ad-banner"], [class*="ad_banner"], iframe[src*="ad"]';
          document.querySelectorAll(sel).forEach(function(el) {
            el.style.display = 'none';
          });
        } catch(e) {}
      })();
    ''';
    _controller.runJavaScript(jsClean);
  }

  void _navigateToUrl(String input) {
    String finalUrl = input.trim();
    if (finalUrl.isEmpty) return;

    if (!finalUrl.startsWith('http://') && !finalUrl.startsWith('https://')) {
      if (finalUrl.contains('.') && !finalUrl.contains(' ')) {
        finalUrl = 'https://$finalUrl';
      } else {
        // استخدام محرك البحث المفضل المختار من المستخدم
        final searchBase = _searchEngines[_selectedSearchEngine] ?? 'https://www.google.com/search?q=';
        finalUrl = '$searchBase${Uri.encodeComponent(finalUrl)}';
      }
    }

    _urlController.text = finalUrl;
    // عند الدخول لموقع تكبر الشاشة لتغطية كامل التطبيق
    setState(() {
      _hasEnteredSite = true;
      _backend.isBrowserExpanded.value = true;
    });
    _controller.loadRequest(Uri.parse(finalUrl));
    FocusScope.of(context).unfocus();
  }

  void _returnToHome() {
    setState(() {
      _hasEnteredSite = false;
      _backend.isBrowserExpanded.value = false;
      _currentUrl = 'https://www.google.com';
      _urlController.text = 'https://www.google.com';
    });
    _controller.loadRequest(Uri.parse('https://www.google.com'));
  }

  void _toggleFullScreenCoverage() {
    setState(() {
      final nextState = !_backend.isBrowserExpanded.value;
      _backend.isBrowserExpanded.value = nextState;
      _hasEnteredSite = nextState;
    });
  }

  void _toggleDesktopMode() {
    setState(() {
      _isDesktopMode = !_isDesktopMode;
    });

    final userAgent = _isDesktopMode
        ? 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
        : '';
    _controller.setUserAgent(userAgent);
    _controller.reload();
  }

  // تفعيل/تعطيل التصفح الخفي (Incognito Mode)
  void _toggleIncognitoMode() async {
    setState(() {
      _isIncognitoMode = !_isIncognitoMode;
    });

    if (_isIncognitoMode) {
      try {
        final cookieManager = WebViewCookieManager();
        await cookieManager.clearCookies();
        await _controller.clearCache();
        await _controller.clearLocalStorage();
      } catch (_) {}

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🕶️ تم تفعيل الوضع الخفي: لن يتم حفظ السجل أو الكوكيز'),
          backgroundColor: Color(0xFF3F51B5),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تعطيل الوضع الخفي'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  // تبديل مانع الإعلانات
  void _toggleAdBlocker() async {
    setState(() {
      _adBlockerEnabled = !_adBlockerEnabled;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('browser_adblock_enabled', _adBlockerEnabled);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_adBlockerEnabled ? '🛡️ تم تفعيل مانع الإعلانات' : 'تم تعطيل مانع الإعلانات'),
        duration: const Duration(seconds: 1),
      ),
    );
    _controller.reload();
  }

  // اختيار محرك البحث
  void _showSearchEngineDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Row(
          children: [
            Icon(Icons.search_rounded, color: AppColors.cyan),
            SizedBox(width: 8),
            Text('محرك البحث الافتراضي', style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _searchEngines.keys.map((engine) {
            final isSelected = engine == _selectedSearchEngine;
            return RadioListTile<String>(
              value: engine,
              groupValue: _selectedSearchEngine,
              activeColor: AppColors.cyan,
              title: Text(engine, style: TextStyle(color: isSelected ? AppColors.cyan : Colors.white)),
              onChanged: (val) async {
                if (val != null) {
                  setState(() => _selectedSearchEngine = val);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('browser_search_engine', val);
                  Navigator.pop(ctx);
                }
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  // عرض الإشارات المرجعية
  void _showBookmarksSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.65,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.bookmarks_rounded, color: AppColors.cyan),
                        SizedBox(width: 8),
                        Text('الإشارات المرجعية المحفوظة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    Text('${_bookmarks.length}', style: const TextStyle(color: AppColors.textMuted)),
                  ],
                ),
                const Divider(color: Colors.white12, height: 20),
                Expanded(
                  child: _bookmarks.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.star_outline_rounded, color: Colors.white24, size: 48),
                              SizedBox(height: 8),
                              Text('لا توجد إشارات مرجعية محفوظة بعد', style: TextStyle(color: AppColors.textMuted)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: _bookmarks.length,
                          separatorBuilder: (_, __) => const Divider(color: Colors.white10),
                          itemBuilder: (context, idx) {
                            final b = _bookmarks[idx];
                            return ListTile(
                              leading: const Icon(Icons.bookmark_rounded, color: AppColors.cyan),
                              title: Text(
                                b['title'] ?? b['url'] ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                b['url'] ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                                onPressed: () {
                                  _bookmarks.removeAt(idx);
                                  _saveBookmarks();
                                  setSheetState(() {});
                                  setState(() {});
                                },
                              ),
                              onTap: () {
                                Navigator.pop(ctx);
                                _navigateToUrl(b['url'] ?? '');
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // قائمة الإجراءات (Page Actions Menu)
  void _showPageActionsMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 15),
            Text(
              _currentTitle.isNotEmpty ? _currentTitle : _currentUrl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 15),
            const Divider(color: Colors.white12),
            Wrap(
              runSpacing: 8,
              children: [
                ListTile(
                  leading: Icon(_backend.isBrowserExpanded.value ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded, color: AppColors.cyan),
                  title: Text(_backend.isBrowserExpanded.value ? 'تصغير الشاشة وإظهار القوائم' : 'تكبير الشاشة لتغطية كامل التطبيق', style: const TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _toggleFullScreenCoverage();
                  },
                ),
                ListTile(
                  leading: Icon(_isCurrentBookmarked ? Icons.star_rounded : Icons.star_outline_rounded, color: AppColors.cyan),
                  title: Text(_isCurrentBookmarked ? 'إزالة من الإشارات المرجعية' : 'إضافة إلى الإشارات المرجعية ⭐', style: const TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _toggleBookmark();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.bookmarks_outlined, color: AppColors.cyan),
                  title: const Text('عرض الإشارات المرجعية 🔖', style: TextStyle(color: Colors.white)),
                  trailing: Text('${_bookmarks.length}', style: const TextStyle(color: AppColors.textMuted)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showBookmarksSheet();
                  },
                ),
                ListTile(
                  leading: Icon(_adBlockerEnabled ? Icons.shield_rounded : Icons.shield_outlined, color: _adBlockerEnabled ? Colors.greenAccent : Colors.white54),
                  title: Text('مانع الإعلانات 🛡️ (${_adBlockerEnabled ? "مفعل" : "معطل"})', style: const TextStyle(color: Colors.white)),
                  trailing: Text('$_blockedAdsCount محجوب', style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _toggleAdBlocker();
                  },
                ),
                ListTile(
                  leading: Icon(_isIncognitoMode ? Icons.visibility_off : Icons.visibility, color: _isIncognitoMode ? const Color(0xFF7986CB) : Colors.white70),
                  title: Text('الوضع الخفي 🕶️ (${_isIncognitoMode ? "نشط" : "معطل"})', style: const TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _toggleIncognitoMode();
                  },
                ),
                ListTile(
                  leading: Icon(_isDesktopMode ? Icons.desktop_windows_rounded : Icons.phone_android_rounded, color: AppColors.cyan),
                  title: Text(_isDesktopMode ? 'العرض بنسخة الهاتف' : 'العرض بنسخة سطح المكتب 💻', style: const TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _toggleDesktopMode();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.search_rounded, color: AppColors.cyan),
                  title: const Text('محرك البحث المفضل', style: TextStyle(color: Colors.white)),
                  trailing: Text(_selectedSearchEngine, style: const TextStyle(color: AppColors.cyan, fontWeight: FontWeight.bold)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showSearchEngineDialog();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.copy_rounded, color: Colors.white70),
                  title: const Text('نسخ رابط الصفحة 📋', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(ctx);
                    Clipboard.setData(ClipboardData(text: _currentUrl));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تم نسخ الرابط إلى الحافظة!'), duration: Duration(seconds: 1)),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.share_rounded, color: Colors.white70),
                  title: const Text('مشاركة الصفحة ↗️', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(ctx);
                    Share.share(_currentUrl, subject: _currentTitle);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.open_in_browser_rounded, color: AppColors.magenta),
                  title: const Text('فتح في متصفح خارجي 🌐', style: TextStyle(color: Colors.white)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final uri = Uri.tryParse(_currentUrl);
                    if (uri != null) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_canGoBack && !_backend.isBrowserExpanded.value,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        if (_canGoBack) {
          _controller.goBack();
        } else if (_backend.isBrowserExpanded.value) {
          setState(() {
            _backend.isBrowserExpanded.value = false;
            _hasEnteredSite = false;
          });
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              // شريط العنوان والتحكم المطور للمتصفح
              Container(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                decoration: BoxDecoration(
                  color: _isIncognitoMode ? const Color(0xFF16162A) : AppColors.surface,
                  border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.06))),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        // زر الصفحة الرئيسية / تصغير الشاشة عند تصفح المواقع
                        if (_backend.isBrowserExpanded.value || _hasEnteredSite)
                          IconButton(
                            icon: const Icon(Icons.home_rounded, size: 22, color: AppColors.cyan),
                            onPressed: _returnToHome,
                            tooltip: 'الرئيسية واستعادة القوائم',
                            visualDensity: VisualDensity.compact,
                          ),
                        IconButton(
                          icon: Icon(Icons.arrow_back_ios_rounded, size: 18, color: _canGoBack ? Colors.white : Colors.white24),
                          onPressed: _canGoBack ? () => _controller.goBack() : null,
                          tooltip: 'رجوع',
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          icon: Icon(Icons.arrow_forward_ios_rounded, size: 18, color: _canGoForward ? Colors.white : Colors.white24),
                          onPressed: _canGoForward ? () => _controller.goForward() : null,
                          tooltip: 'تقدم',
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          icon: Icon(_isLoading ? Icons.close_rounded : Icons.refresh_rounded, size: 20, color: Colors.white70),
                          onPressed: () {
                            if (_isLoading) {
                              _controller.runJavaScript('window.stop();');
                            } else {
                              _controller.reload();
                            }
                          },
                          tooltip: 'تحديث',
                          visualDensity: VisualDensity.compact,
                        ),
                        Expanded(
                          child: Container(
                            height: 38,
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.35),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _isIncognitoMode ? const Color(0xFF7986CB) : Colors.white12,
                              ),
                            ),
                            child: TextField(
                              controller: _urlController,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              textInputAction: TextInputAction.go,
                              onSubmitted: _navigateToUrl,
                              decoration: InputDecoration(
                                hintText: _isIncognitoMode ? '🕶️ بحث خفي أو رابط...' : 'ابحث أو أدخل رابط...',
                                hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                                prefixIcon: Icon(
                                  _isIncognitoMode ? Icons.visibility_off_rounded : Icons.search_rounded,
                                  size: 18,
                                  color: _isIncognitoMode ? const Color(0xFF7986CB) : AppColors.cyan,
                                ),
                                suffixIcon: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_adBlockerEnabled)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                        margin: const EdgeInsets.only(right: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.greenAccent.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.shield_rounded, color: Colors.greenAccent, size: 12),
                                            const SizedBox(width: 3),
                                            Text('$_blockedAdsCount', style: const TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                      ),
                                    IconButton(
                                      icon: Icon(
                                        _isCurrentBookmarked ? Icons.star_rounded : Icons.star_outline_rounded,
                                        size: 18,
                                        color: _isCurrentBookmarked ? AppColors.cyan : Colors.white54,
                                      ),
                                      onPressed: _toggleBookmark,
                                      tooltip: 'إشارة مرجعية',
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    if (_urlController.text.isNotEmpty)
                                      IconButton(
                                        icon: const Icon(Icons.clear, size: 16, color: Colors.white54),
                                        onPressed: () => _urlController.clear(),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                  ],
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                              ),
                            ),
                          ),
                        ),
                        // زر تبديل وضع ملء الشاشة الكامل لتغطية التطبيق
                        IconButton(
                          icon: Icon(
                            _backend.isBrowserExpanded.value ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                            color: _backend.isBrowserExpanded.value ? AppColors.cyan : Colors.white70,
                            size: 22,
                          ),
                          tooltip: _backend.isBrowserExpanded.value ? 'تصغير الشاشة' : 'تكبير الشاشة لتغطية التطبيق',
                          onPressed: _toggleFullScreenCoverage,
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          icon: const Icon(Icons.more_vert_rounded, color: Colors.white70, size: 22),
                          tooltip: 'قائمة المتصفح',
                          onPressed: _showPageActionsMenu,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    if (_isLoading)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _progress,
                            minHeight: 2.5,
                            backgroundColor: Colors.transparent,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _isIncognitoMode ? const Color(0xFF7986CB) : AppColors.cyan,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // شريط اختصارات المنصات السريع (يختفي عند تصفح المواقع لتوسيع شاشة العرض لأقصى مساحة)
              if (!_backend.isBrowserExpanded.value && !_hasEnteredSite)
                Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight.withOpacity(0.25),
                    border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.04))),
                  ),
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: _quickShortcuts.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (ctx, i) {
                      final s = _quickShortcuts[i];
                      return Center(
                        child: InkWell(
                          onTap: () => _navigateToUrl(s['url']),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.04),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white.withOpacity(0.08)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(s['icon'] as IconData, size: 14, color: s['color'] as Color),
                                const SizedBox(width: 6),
                                Text(
                                  s['name'] as String,
                                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

              // عرض صفحة الويب بكامل المساحة المتاحة للشاشة بدون أي عوائق أو أشرطة تحميل
              Expanded(
                child: WebViewWidget(controller: _controller),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
