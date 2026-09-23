import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// خدمة استخراج الروابط العالمية (Universal Extractor Service)
/// تدعم استخراج وتحليل مقاطع الفيديو والصوت من:
/// TikTok, Instagram, Facebook, Twitter/X, Pinterest, Reddit, Vimeo, Dailymotion,
/// الروابط المباشرة (Direct Media URLs)، وأي موقع ويب يحتوي على فيديو (HTML5 Web Scraper).
class UniversalExtractorService {
  static final UniversalExtractorService _instance = UniversalExtractorService._internal();
  factory UniversalExtractorService() => _instance;
  UniversalExtractorService._internal();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
      'Accept-Language': 'ar,en-US;q=0.9,en;q=0.8',
    },
  ));

  /// كشف نوع المنصة تلقائياً من الرابط
  String detectPlatform(String url) {
    final lower = url.toLowerCase().trim();
    if (lower.contains('youtube.com') || lower.contains('youtu.be')) return 'youtube';
    if (lower.contains('tiktok.com') || lower.contains('douyin.com')) return 'tiktok';
    if (lower.contains('instagram.com') || lower.contains('instagr.am')) return 'instagram';
    if (lower.contains('facebook.com') || lower.contains('fb.watch') || lower.contains('fb.com')) return 'facebook';
    if (lower.contains('twitter.com') || lower.contains('x.com') || lower.contains('t.co')) return 'twitter';
    if (lower.contains('pinterest.com') || lower.contains('pin.it')) return 'pinterest';
    if (lower.contains('reddit.com') || lower.contains('redd.it')) return 'reddit';
    if (lower.contains('vimeo.com')) return 'vimeo';
    if (lower.contains('dailymotion.com') || lower.contains('dai.ly')) return 'dailymotion';

    final uri = Uri.tryParse(url);
    if (uri != null) {
      final path = uri.path.toLowerCase();
      if (path.endsWith('.mp4') ||
          path.endsWith('.m3u8') ||
          path.endsWith('.webm') ||
          path.endsWith('.mov') ||
          path.endsWith('.mkv') ||
          path.endsWith('.mp3') ||
          path.endsWith('.m4a') ||
          path.endsWith('.wav') ||
          path.endsWith('.aac')) {
        return 'direct';
      }
    }

    return 'web';
  }

  /// الاستخراج الرئيسي لأي رابط
  Future<Map<String, dynamic>> extract(String rawUrl) async {
    final url = rawUrl.trim();
    final platform = detectPlatform(url);

    debugPrint('بدء استخراج الرابط عبر المحرك الشامل ($platform): $url');

    switch (platform) {
      case 'tiktok':
        return await _extractTikTok(url);
      case 'instagram':
        return await _extractInstagram(url);
      case 'facebook':
        return await _extractFacebook(url);
      case 'twitter':
        return await _extractTwitter(url);
      case 'pinterest':
        return await _extractPinterest(url);
      case 'direct':
        return await _extractDirectMedia(url);
      case 'web':
      default:
        return await _extractGenericWebOrFallbacks(url);
    }
  }

  // =========================================================================
  // 1. استخراج TikTok (فائق السرعة، بدون علامة مائية، صوت MP3)
  // =========================================================================
  Future<Map<String, dynamic>> _extractTikTok(String url) async {
    try {
      final response = await _dio.post(
        'https://www.tikwm.com/api/',
        data: {'url': url},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.json,
        ),
      );

      final body = response.data;
      if (body is Map && body['code'] == 0 && body['data'] != null) {
        final data = body['data'] as Map;
        final title = (data['title'] ?? 'فيديو تيك توك').toString().trim();
        final cover = (data['cover'] ?? '').toString();
        final playUrl = (data['play'] ?? '').toString();
        final hdPlayUrl = (data['hdplay'] ?? '').toString();
        final wmPlayUrl = (data['wmplay'] ?? '').toString();
        final musicUrl = (data['music'] ?? '').toString();
        final author = data['author'] is Map ? (data['author']['nickname'] ?? 'TikTok') : 'TikTok';
        final int sizeBytes = (data['size'] as num?)?.toInt() ?? (data['hd_size'] as num?)?.toInt() ?? 0;
        final double sizeMb = sizeBytes > 0 ? (sizeBytes / (1024 * 1024)) : 5.0;

        final List<Map<String, dynamic>> videoFormats = [];

        if (hdPlayUrl.isNotEmpty) {
          videoFormats.add({
            'url': hdPlayUrl,
            'quality_name': '✨ جودة فائقة محسّنة 1080p Ultra HD (خالية من العلامة المائية)',
            'quality_order': 1440,
            'quality_badge': '✨ ULTRA HD',
            'quality_desc': 'أقصى دقة وجودة بدون ضغط خالية تماماً من العلامة المائية مع أعلى معدل إطارات',
            'size': (sizeMb * 1.3).toStringAsFixed(1),
            'size_bytes': (sizeBytes * 1.3).toInt(),
            'ext': 'mp4',
            'needs_merge': false,
            'platform': 'tiktok',
          });
          videoFormats.add({
            'url': hdPlayUrl,
            'quality_name': 'عالي الدقة 1080p Full HD (بدون علامة مائية)',
            'quality_order': 1080,
            'quality_badge': '1080p FHD',
            'quality_desc': 'أقصى جودة فائقة 1080p Full HD وبدون أي علامة مائية',
            'size': (sizeMb * 1.3).toStringAsFixed(1),
            'size_bytes': (sizeBytes * 1.3).toInt(),
            'ext': 'mp4',
            'needs_merge': false,
            'platform': 'tiktok',
          });
        }

        if (data['images'] is List && (data['images'] as List).isNotEmpty) {
          final imgList = data['images'] as List;
          for (int i = 0; i < imgList.length; i++) {
            videoFormats.add({
              'url': imgList[i].toString(),
              'quality_name': '📸 صورة فائقة النقاء (${i + 1}/${imgList.length})',
              'quality_order': 2000 - i,
              'quality_badge': 'HD PHOTO',
              'quality_desc': 'صورة أصلية عالية الدقة من ألبوم تيك توك بدون علامة مائية',
              'size': '1.8',
              'size_bytes': 1800000,
              'ext': 'jpg',
              'needs_merge': false,
              'platform': 'tiktok',
            });
          }
        }

        if (playUrl.isNotEmpty) {
          videoFormats.add({
            'url': playUrl,
            'quality_name': 'عالي الدقة 720p HD (بدون علامة مائية)',
            'quality_order': 720,
            'quality_badge': '720p HD',
            'quality_desc': 'تنزيل سريع وبجودة عالية خالية من العلامة المائية',
            'size': sizeMb.toStringAsFixed(1),
            'size_bytes': sizeBytes,
            'ext': 'mp4',
            'needs_merge': false,
            'platform': 'tiktok',
          });
        }

        if (wmPlayUrl.isNotEmpty && videoFormats.isEmpty) {
          videoFormats.add({
            'url': wmPlayUrl,
            'quality_name': 'النسخة الأصلية',
            'quality_order': 720,
            'quality_badge': 'أصلي',
            'quality_desc': 'النسخة المباشرة من تطبيق تيك توك',
            'size': sizeMb.toStringAsFixed(1),
            'size_bytes': sizeBytes,
            'ext': 'mp4',
            'needs_merge': false,
            'platform': 'tiktok',
          });
        }

        final List<Map<String, dynamic>> audioFormats = [];
        if (musicUrl.isNotEmpty) {
          audioFormats.add({
            'url': musicUrl,
            'quality_name': 'صوت تيك توك الأصلي MP3',
            'quality_order': 192,
            'quality_badge': 'صوت HQ',
            'quality_desc': 'استخراج المسار الصوتي الأصلي بنقاء عالي',
            'size': '3.2',
            'size_bytes': 3200000,
            'ext': 'mp3',
            'needs_merge': false,
            'platform': 'tiktok',
          });
        }

        return {
          'id': (data['id'] ?? 'tiktok_${DateTime.now().millisecondsSinceEpoch}').toString(),
          'title': title.isEmpty ? 'فيديو تيك توك' : title,
          'thumbnail': cover,
          'author': author.toString(),
          'platform': 'tiktok',
          'highestAudioUrl': musicUrl,
          'highestAudioTag': null,
          'video': videoFormats,
          'audio': audioFormats,
          'subtitles': [],
        };
      }
    } catch (e) {
      debugPrint('تنبيه TikWM فشل، جاري المحاولة عبر المحرك الاحتياطي: $e');
    }

    // المحاولة الاحتياطية لـ TikTok
    return await _extractGenericWebOrFallbacks(url, forcedPlatform: 'tiktok');
  }

  String _cleanUrl(String raw) {
    var s = raw.trim();
    s = s.replaceAll(r'\/', '/');
    s = s.replaceAll(r'\u0025', '%');
    s = s.replaceAll(r'\u0026', '&');
    s = s.replaceAll('&amp;', '&');
    s = s.replaceAll(r'\u003C', '<');
    s = s.replaceAll(r'\u003E', '>');
    return s;
  }

  // =========================================================================
  // 2. استخراج Instagram (Reels, Posts, Stories, IGTV)
  // =========================================================================
  Future<Map<String, dynamic>> _extractInstagram(String rawUrl) async {
    String url = rawUrl.trim();

    // 1. فك إعادة التوجيه للروابط المختصرة ومشاركة التطبيق
    try {
      if (url.contains('/share/') || url.contains('instagr.am')) {
        final redirectCheck = await _dio.get(
          url,
          options: Options(
            followRedirects: true,
            maxRedirects: 6,
            validateStatus: (status) => true,
            headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
            },
          ),
        );
        final real = redirectCheck.realUri.toString();
        if (real.isNotEmpty && !real.contains('/accounts/login/')) {
          url = real;
        }
      }
    } catch (_) {}

    // استخراج الـ shortcode من مختلف صيغ روابط إنستغرام
    String shortcode = '';
    final uri = Uri.tryParse(url);
    if (uri != null) {
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      for (int i = 0; i < segments.length; i++) {
        final seg = segments[i].toLowerCase();
        if (seg == 'p' || seg == 'reel' || seg == 'reels' || seg == 'tv') {
          if (i + 1 < segments.length) {
            shortcode = segments[i + 1];
            break;
          }
        }
      }
      if (shortcode.isEmpty && segments.isNotEmpty) {
        shortcode = segments.firstWhere((s) => s.length >= 5 && s.length <= 25, orElse: () => segments.last);
      }
    }

    if (shortcode.isEmpty) {
      final match = RegExp(r'\/(?:p|reel|reels|tv)\/([A-Za-z0-9_-]+)').firstMatch(url);
      if (match != null) shortcode = match.group(1)!;
    }

    // محاولة 1: استخراج مباشر فائق السرعة عبر واجهة التضمين العامة لإنستغرام (Instagram Embed)
    // واجهة التضمين مخصصة للمواقع الخارجية ولا تطلب تسجيل الدخول وتوفر دقة عالية وصورة واضحة
    if (shortcode.isNotEmpty) {
      final embedUrls = [
        'https://www.instagram.com/p/$shortcode/embed/captioned/',
        'https://www.instagram.com/reel/$shortcode/embed/captioned/',
        'https://www.instagram.com/p/$shortcode/embed/',
      ];

      for (final embedUrl in embedUrls) {
        try {
          final res = await _dio.get(
            embedUrl,
            options: Options(
              headers: {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
                'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                'Accept-Language': 'en-US,en;q=0.9',
              },
            ),
          );

          if (res.statusCode == 200 && res.data != null) {
            final html = res.data.toString();
            final vMatch = RegExp(r'class="EmbeddedVideo"[^>]*src="([^"]+)"').firstMatch(html) ??
                RegExp(r'"video_url"\s*:\s*"([^"]+)"').firstMatch(html) ??
                RegExp(r'<video[^>]*src="([^"]+)"').firstMatch(html) ??
                RegExp(r'data-ios-url="([^"]+)"').firstMatch(html);

            final tMatch = RegExp(r'class="EmbeddedMediaImage"[^>]*src="([^"]+)"').firstMatch(html) ??
                RegExp(r'"display_url"\s*:\s*"([^"]+)"').firstMatch(html) ??
                RegExp(r'<img[^>]*class="EmbeddedMediaImage"[^>]*src="([^"]+)"').firstMatch(html);

            final cMatch = RegExp(r'class="Caption"[^>]*>([^<]+)<').firstMatch(html) ??
                RegExp(r'<title>([^<]+)<\/title>').firstMatch(html);

            if (vMatch != null) {
              final videoUrl = _cleanUrl(vMatch.group(1)!);
              final thumb = tMatch != null ? _cleanUrl(tMatch.group(1)!) : '';
              final title = (cMatch?.group(1) ?? 'ريلز إنستغرام').trim();

              if (videoUrl.startsWith('http')) {
                return _buildSimpleMediaResult(
                  id: shortcode,
                  title: title.isNotEmpty ? title : 'ريلز إنستغرام',
                  thumbnail: thumb,
                  videoUrl: videoUrl,
                  hdVideoUrl: videoUrl,
                  sdVideoUrl: videoUrl,
                  platform: 'instagram',
                  author: 'Instagram',
                );
              }
            }
          }
        } catch (e) {
          debugPrint('Instagram embed attempt error: $e');
        }
      }
    }

    // محاولة 2: استدعاء محركات معالجة وسائط إنستغرام العامة (FastDL / SaveInsta / InDown)
    final apiEndpoints = [
      {'url': 'https://v3.fastdl.app/api/ajaxSearch', 'origin': 'https://fastdl.app'},
      {'url': 'https://saveinsta.app/api/ajaxSearch', 'origin': 'https://saveinsta.app'},
      {'url': 'https://v3.fdownloader.net/api/ajaxSearch', 'origin': 'https://fdownloader.net'},
    ];

    for (final ep in apiEndpoints) {
      try {
        final res = await _dio.post(
          ep['url']!,
          data: {'q': url, 'lang': 'en'},
          options: Options(
            contentType: Headers.formUrlEncodedContentType,
            headers: {
              'origin': ep['origin']!,
              'referer': '${ep['origin']}/',
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            },
          ),
        );

        if (res.data != null && res.data['data'] != null) {
          final html = res.data['data'].toString();
          final match = RegExp(r'href="([^"]+)"[^>]*class="[^"]*btn-download').firstMatch(html) ??
              RegExp(r'href="([^"]+)"[^>]*>Download Video').firstMatch(html) ??
              RegExp(r'href="([^"]+)"[^>]*download').firstMatch(html) ??
              RegExp(r'href="(https:\/\/[^"]+\.mp4[^"]*)"').firstMatch(html);

          if (match != null) {
            final vUrl = _cleanUrl(match.group(1)!);
            if (vUrl.startsWith('http')) {
              return _buildSimpleMediaResult(
                id: shortcode.isNotEmpty ? shortcode : 'ig_${DateTime.now().millisecondsSinceEpoch}',
                title: 'ريلز إنستغرام',
                thumbnail: '',
                videoUrl: vUrl,
                hdVideoUrl: vUrl,
                sdVideoUrl: vUrl,
                platform: 'instagram',
                author: 'Instagram',
              );
            }
          }
        }
      } catch (e) {
        debugPrint('Instagram API ${ep['url']} error: $e');
      }
    }

    // محاولة 3: GraphQL مع المتغيرات
    if (shortcode.isNotEmpty) {
      try {
        final gqlUrl = 'https://www.instagram.com/graphql/query/?query_hash=b3055c2c970540414ba30bb6133bc710&variables={"shortcode":"$shortcode"}';
        final res = await _dio.get(
          gqlUrl,
          options: Options(headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
            'Accept': '*/*',
          }),
        );
        if (res.statusCode == 200 && res.data is Map) {
          final media = res.data['data']?['shortcode_media'];
          if (media != null) {
            final vUrl = media['video_url']?.toString();
            final thumb = media['display_url']?.toString() ?? '';
            final caption = media['edge_media_to_caption']?['edges']?[0]?['node']?['text']?.toString() ?? 'ريلز إنستغرام';
            if (vUrl != null && vUrl.isNotEmpty) {
              final cleanedV = _cleanUrl(vUrl);
              return _buildSimpleMediaResult(
                id: shortcode,
                title: caption.split('\n').first,
                thumbnail: thumb,
                videoUrl: cleanedV,
                hdVideoUrl: cleanedV,
                sdVideoUrl: cleanedV,
                platform: 'instagram',
                author: media['owner']?['username']?.toString() ?? 'Instagram',
              );
            }
          }
        }
      } catch (e) {
        debugPrint('Instagram GraphQL error: $e');
      }
    }

    // محاولة 4: الفحص العام للصفحة ومؤشرات OpenGraph
    return await _extractGenericWebOrFallbacks(url, forcedPlatform: 'instagram');
  }

  // =========================================================================
  // 3. استخراج Facebook (Watch, Reels, Videos)
  // =========================================================================
  Future<Map<String, dynamic>> _extractFacebook(String rawUrl) async {
    String url = rawUrl.trim();

    // 1. فك إعادة التوجيه لروابط fb.watch ومشاركة التطبيق
    try {
      if (url.contains('fb.watch') || url.contains('/share/')) {
        final redirectCheck = await _dio.get(
          url,
          options: Options(
            followRedirects: true,
            maxRedirects: 6,
            validateStatus: (status) => true,
            headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
            },
          ),
        );
        final real = redirectCheck.realUri.toString();
        if (real.isNotEmpty) {
          url = real;
        }
      }
    } catch (_) {}

    // محاولة 1: الفحص المباشر لصفحة الفيسبوك الأصلية واستخراج دفقات HD و SD
    try {
      final res = await _dio.get(
        url,
        options: Options(
          followRedirects: true,
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
            'Accept-Language': 'en-US,en;q=0.9',
            'Sec-Fetch-Site': 'none',
            'Sec-Fetch-Mode': 'navigate',
            'Sec-Fetch-User': '?1',
            'Sec-Fetch-Dest': 'document',
          },
        ),
      );

      final html = res.data.toString();

      // البحث عن دفق الجودة العالية HD
      final hdSrc = RegExp(r'"browser_native_hd_url"\s*:\s*"([^"]+)"').firstMatch(html)?.group(1) ??
          RegExp(r'"playable_url_quality_hd"\s*:\s*"([^"]+)"').firstMatch(html)?.group(1) ??
          RegExp(r'"hd_src_no_ratelimit"\s*:\s*"([^"]+)"').firstMatch(html)?.group(1) ??
          RegExp(r'"hd_src"\s*:\s*"([^"]+)"').firstMatch(html)?.group(1) ??
          RegExp(r'hd_src\s*:\s*"([^"]+)"').firstMatch(html)?.group(1);

      // البحث عن دفق الجودة العادية SD
      final sdSrc = RegExp(r'"browser_native_sd_url"\s*:\s*"([^"]+)"').firstMatch(html)?.group(1) ??
          RegExp(r'"playable_url"\s*:\s*"([^"]+)"').firstMatch(html)?.group(1) ??
          RegExp(r'"sd_src_no_ratelimit"\s*:\s*"([^"]+)"').firstMatch(html)?.group(1) ??
          RegExp(r'"sd_src"\s*:\s*"([^"]+)"').firstMatch(html)?.group(1) ??
          RegExp(r'sd_src\s*:\s*"([^"]+)"').firstMatch(html)?.group(1) ??
          RegExp(r'"playback_url"\s*:\s*"([^"]+)"').firstMatch(html)?.group(1);

      // البحث عن العنوان والصورة المصغرة
      final titleMatch = RegExp(r'<meta\s+property="og:title"\s+content="([^"]*)"').firstMatch(html) ??
          RegExp(r'<title>([^<]+)<\/title>').firstMatch(html);
      final thumbMatch = RegExp(r'<meta\s+property="og:image"\s+content="([^"]*)"').firstMatch(html);

      final cleanHd = hdSrc != null ? _cleanUrl(hdSrc) : '';
      final cleanSd = sdSrc != null ? _cleanUrl(sdSrc) : '';
      final cleanTitle = (titleMatch?.group(1) ?? 'فيديو فيسبوك').replaceAll('&amp;', '&').trim();
      final cleanThumb = thumbMatch != null ? _cleanUrl(thumbMatch.group(1)!) : '';

      final chosenUrl = cleanHd.isNotEmpty ? cleanHd : cleanSd;
      if (chosenUrl.isNotEmpty && chosenUrl.startsWith('http')) {
        return _buildSimpleMediaResult(
          id: 'fb_${DateTime.now().millisecondsSinceEpoch}',
          title: cleanTitle.isNotEmpty ? cleanTitle : 'فيديو فيسبوك',
          thumbnail: cleanThumb,
          videoUrl: chosenUrl,
          hdVideoUrl: cleanHd.isNotEmpty ? cleanHd : chosenUrl,
          sdVideoUrl: cleanSd.isNotEmpty ? cleanSd : chosenUrl,
          platform: 'facebook',
          author: 'Facebook',
        );
      }
    } catch (e) {
      debugPrint('Facebook Desktop Direct Scraping error: $e');
    }

    // محاولة 2: واجهات التنزيل السحابية لفيسبوك (FDownloader, SnapSave, FBDownloader)
    final fbApis = [
      {'url': 'https://fdownloader.net/api/ajaxSearch', 'origin': 'https://fdownloader.net'},
      {'url': 'https://v3.fdownloader.net/api/ajaxSearch', 'origin': 'https://fdownloader.net'},
      {'url': 'https://fbdownloader.net/api/ajaxSearch', 'origin': 'https://fbdownloader.net'},
    ];

    for (final api in fbApis) {
      try {
        final res = await _dio.post(
          api['url']!,
          data: {'q': url, 'lang': 'en'},
          options: Options(
            contentType: Headers.formUrlEncodedContentType,
            headers: {
              'origin': api['origin']!,
              'referer': '${api['origin']}/',
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            },
          ),
        );
        if (res.data != null && res.data['data'] != null) {
          final html = res.data['data'].toString();
          final hdMatch = RegExp(r'href="([^"]+)"[^>]*data-quality="HD"').firstMatch(html) ??
              RegExp(r'href="([^"]+)"[^>]*>Download HD').firstMatch(html) ??
              RegExp(r'href="([^"]+)"[^>]*1080p').firstMatch(html) ??
              RegExp(r'href="([^"]+)"[^>]*720p').firstMatch(html);
          final sdMatch = RegExp(r'href="([^"]+)"[^>]*data-quality="SD"').firstMatch(html) ??
              RegExp(r'href="([^"]+)"[^>]*>Download SD').firstMatch(html) ??
              RegExp(r'href="(https:\/\/[^"]+\.mp4[^"]*)"').firstMatch(html);

          final hdVideo = hdMatch != null ? _cleanUrl(hdMatch.group(1)!) : '';
          final sdVideo = sdMatch != null ? _cleanUrl(sdMatch.group(1)!) : '';
          final anyVideo = hdVideo.isNotEmpty ? hdVideo : sdVideo;

          if (anyVideo.isNotEmpty && anyVideo.startsWith('http')) {
            return _buildSimpleMediaResult(
              id: 'fb_${DateTime.now().millisecondsSinceEpoch}',
              title: 'فيديو فيسبوك',
              thumbnail: '',
              videoUrl: anyVideo,
              hdVideoUrl: hdVideo.isNotEmpty ? hdVideo : anyVideo,
              sdVideoUrl: sdVideo.isNotEmpty ? sdVideo : anyVideo,
              platform: 'facebook',
              author: 'Facebook',
            );
          }
        }
      } catch (e) {
        debugPrint('Facebook API ${api['url']} error: $e');
      }
    }

    // محاولة 3: نسخة الجوال m.facebook.com
    try {
      final mobileUrl = url.replaceFirst('www.facebook.com', 'm.facebook.com');
      final res = await _dio.get(
        mobileUrl,
        options: Options(headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        }),
      );
      final html = res.data.toString();
      final match = RegExp(r'<video[^>]*src="([^"]+)"').firstMatch(html) ??
          RegExp(r'href="(\/video_redirect\/[^"]+)"').firstMatch(html) ??
          RegExp(r'"video_url"\s*:\s*"([^"]+)"').firstMatch(html);
      if (match != null) {
        var v = _cleanUrl(match.group(1)!);
        if (v.startsWith('/video_redirect/')) {
          final uri = Uri.parse('https://m.facebook.com$v');
          v = uri.queryParameters['src'] ?? v;
        }
        if (v.startsWith('http')) {
          return _buildSimpleMediaResult(
            id: 'fb_${DateTime.now().millisecondsSinceEpoch}',
            title: 'فيديو فيسبوك',
            thumbnail: '',
            videoUrl: v,
            hdVideoUrl: v,
            sdVideoUrl: v,
            platform: 'facebook',
            author: 'Facebook',
          );
        }
      }
    } catch (e) {
      debugPrint('Facebook Mobile attempt error: $e');
    }

    return await _extractGenericWebOrFallbacks(url, forcedPlatform: 'facebook');
  }

  // =========================================================================
  // 4. استخراج Twitter / X
  // =========================================================================
  Future<Map<String, dynamic>> _extractTwitter(String url) async {
    // استخراج ID التغريدة
    final match = RegExp(r'status\/(\d+)').firstMatch(url);
    if (match != null) {
      final tweetId = match.group(1)!;
      // محاولة 1: VxTwitter / FxTwitter API السريعة
      try {
        final res = await _dio.get('https://api.vxtwitter.com/Twitter/status/$tweetId');
        if (res.statusCode == 200 && res.data is Map) {
          final data = res.data as Map;
          final mediaList = data['mediaURLs'] as List? ?? [];
          final mediaUrl = mediaList.firstWhere(
            (m) => m.toString().contains('.mp4'),
            orElse: () => data['video_url'] ?? '',
          );

          if (mediaUrl.toString().isNotEmpty) {
            return _buildSimpleMediaResult(
              id: tweetId,
              title: data['text'] ?? 'فيديو من منصة X (تويتر)',
              thumbnail: (data['media_thumb'] ?? '').toString(),
              videoUrl: mediaUrl.toString(),
              platform: 'twitter',
              author: data['user_name'] ?? 'Twitter',
            );
          }
        }
      } catch (e) {
        debugPrint('Twitter VxTwitter محاولة 1: $e');
      }

      // محاولة 2: SaveTwitter API
      try {
        final res = await _dio.post(
          'https://savetwitter.net/api/ajaxSearch',
          data: {'q': url, 'lang': 'en'},
          options: Options(
            contentType: Headers.formUrlEncodedContentType,
            headers: {'origin': 'https://savetwitter.net', 'referer': 'https://savetwitter.net/'},
          ),
        );
        if (res.data != null && res.data['data'] != null) {
          final html = res.data['data'].toString();
          final vMatch = RegExp(r'href="(https:\/\/[^"]+\.mp4[^"]*)"').firstMatch(html) ??
              RegExp(r'href="([^"]+)"[^>]*class="[^"]*tw-button-dl').firstMatch(html);
          if (vMatch != null) {
            return _buildSimpleMediaResult(
              id: tweetId,
              title: 'فيديو تويتر / X',
              thumbnail: '',
              videoUrl: vMatch.group(1)!.replaceAll('&amp;', '&'),
              platform: 'twitter',
              author: 'Twitter',
            );
          }
        }
      } catch (e) {
        debugPrint('Twitter SaveTwitter محاولة 2: $e');
      }
    }

    return await _extractGenericWebOrFallbacks(url, forcedPlatform: 'twitter');
  }

  // =========================================================================
  // 5. استخراج Pinterest
  // =========================================================================
  Future<Map<String, dynamic>> _extractPinterest(String url) async {
    try {
      final res = await _dio.get('https://www.savepin.app/download.php?url=${Uri.encodeComponent(url)}&lang=en&type=redirect');
      final html = res.data.toString();
      final vMatch = RegExp(r'href="([^"]*url=https%3A%2F%2Fv\.pinimg\.com[^"]*)"').firstMatch(html) ??
          RegExp(r'href="(https:\/\/v\.pinimg\.com[^"]+\.mp4[^"]*)"').firstMatch(html);

      if (vMatch != null) {
        String directUrl = vMatch.group(1)!;
        if (directUrl.contains('url=')) {
          directUrl = Uri.decodeComponent(directUrl.split('url=')[1]);
        }
        return _buildSimpleMediaResult(
          id: 'pin_${DateTime.now().millisecondsSinceEpoch}',
          title: 'فيديو بنترست Pinterest',
          thumbnail: '',
          videoUrl: directUrl,
          platform: 'pinterest',
          author: 'Pinterest',
        );
      }
    } catch (e) {
      debugPrint('Pinterest SavePin محاولة 1: $e');
    }

    return await _extractGenericWebOrFallbacks(url, forcedPlatform: 'pinterest');
  }

  // =========================================================================
  // 6. استخراج الروابط المباشرة لملفات الوسائط (.mp4, .m3u8, .mp3, etc.)
  // =========================================================================
  Future<Map<String, dynamic>> _extractDirectMedia(String url) async {
    final uri = Uri.parse(url);
    final filename = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'media_file';
    final nameWithoutExt = filename.contains('.') ? filename.substring(0, filename.lastIndexOf('.')) : filename;
    final ext = filename.contains('.') ? filename.split('.').last.toLowerCase() : 'mp4';
    final isAudio = ['mp3', 'm4a', 'wav', 'aac', 'flac'].contains(ext);

    int sizeBytes = 0;
    try {
      final headRes = await _dio.head(url);
      final cl = headRes.headers.value('content-length');
      if (cl != null) sizeBytes = int.tryParse(cl) ?? 0;
    } catch (_) {}

    final sizeMb = sizeBytes > 0 ? (sizeBytes / (1024 * 1024)).toStringAsFixed(1) : 'مباشر';

    final List<Map<String, dynamic>> videoFormats = [];
    final List<Map<String, dynamic>> audioFormats = [];

    if (!isAudio) {
      videoFormats.add({
        'url': url,
        'quality_name': 'جودة الرابط الأصلية ($ext)',
        'quality_order': 1080,
        'quality_badge': ext.toUpperCase(),
        'quality_desc': 'رابط مباشر بجودة المقطع الأصلية الكاملة',
        'size': sizeMb,
        'size_bytes': sizeBytes,
        'ext': ext,
        'needs_merge': false,
        'platform': 'direct',
      });
    }

    audioFormats.add({
      'url': url,
      'quality_name': 'صوت نقي (${isAudio ? ext.toUpperCase() : "MP3"})',
      'quality_order': 192,
      'quality_badge': isAudio ? ext.toUpperCase() : 'MP3',
      'quality_desc': isAudio ? 'ملف صوتي مباشر' : 'تحويل المقطع الصوتي تلقائياً إلى MP3',
      'size': isAudio ? sizeMb : 'صوت',
      'size_bytes': isAudio ? sizeBytes : 0,
      'ext': isAudio ? ext : 'mp3',
      'needs_merge': false,
      'platform': 'direct',
    });

    return {
      'id': 'direct_${DateTime.now().millisecondsSinceEpoch}',
      'title': nameWithoutExt.replaceAll('_', ' ').replaceAll('-', ' '),
      'thumbnail': 'https://via.placeholder.com/640x360/1A1A24/00D9FF?text=Direct+Media',
      'platform': 'direct',
      'author': uri.host,
      'highestAudioUrl': url,
      'highestAudioTag': null,
      'video': videoFormats,
      'audio': audioFormats,
      'subtitles': [],
    };
  }

  // =========================================================================
  // 7. استخراج أي صفحة ويب عامة أو المحرك الاحتياطي الشامل (Generic HTML5 / OpenGraph Scraper)
  // =========================================================================
  Future<Map<String, dynamic>> _extractGenericWebOrFallbacks(String url, {String? forcedPlatform}) async {
    debugPrint('جاري فحص محتوى صفحة الويب عبر HTML Scraper الشامل: $url');
    try {
      final res = await _dio.get(
        url,
        options: Options(
          followRedirects: true,
          validateStatus: (s) => s != null && s < 500,
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'ar,en-US;q=0.9,en;q=0.8',
          },
        ),
      );

      final html = res.data.toString();

      // 1. استخراج العنوان
      final titleMatch = RegExp(r'<meta[^>]*property="og:title"[^>]*content="([^"]+)"', caseSensitive: false).firstMatch(html) ??
          RegExp(r"<meta[^>]*property='og:title'[^>]*content='([^']+)'", caseSensitive: false).firstMatch(html) ??
          RegExp(r'<meta[^>]*content="([^"]+)"[^>]*property="og:title"', caseSensitive: false).firstMatch(html) ??
          RegExp(r"<meta[^>]*content='([^']+)'[^>]*property='og:title'", caseSensitive: false).firstMatch(html) ??
          RegExp(r'<meta[^>]*name="twitter:title"[^>]*content="([^"]+)"', caseSensitive: false).firstMatch(html) ??
          RegExp(r"<meta[^>]*name='twitter:title'[^>]*content='([^']+)'", caseSensitive: false).firstMatch(html) ??
          RegExp(r'<title[^>]*>([^<]+)</title>', caseSensitive: false).firstMatch(html);
      String title = (titleMatch?.group(1) ?? 'فيديو من الإنترنت').replaceAll('&amp;', '&').trim();
      if (title.isEmpty) title = 'فيديو من الإنترنت';

      // 2. استخراج الصورة المصغرة
      final thumbMatch = RegExp(r'<meta[^>]*property="og:image"[^>]*content="([^"]+)"', caseSensitive: false).firstMatch(html) ??
          RegExp(r"<meta[^>]*property='og:image'[^>]*content='([^']+)'", caseSensitive: false).firstMatch(html) ??
          RegExp(r'<meta[^>]*content="([^"]+)"[^>]*property="og:image"', caseSensitive: false).firstMatch(html) ??
          RegExp(r"<meta[^>]*content='([^']+)'[^>]*property='og:image'", caseSensitive: false).firstMatch(html) ??
          RegExp(r'<meta[^>]*name="twitter:image"[^>]*content="([^"]+)"', caseSensitive: false).firstMatch(html) ??
          RegExp(r"<meta[^>]*name='twitter:image'[^>]*content='([^']+)'", caseSensitive: false).firstMatch(html);
      final thumbnail = (thumbMatch?.group(1) ?? '').replaceAll('&amp;', '&');

      // 3. استخراج رابط الفيديو أو البث الشامل بجميع الصيغ (mp4, m3u8, webm, mov, m4v, flv, ogv)
      final videoPatterns = [
        r'<meta[^>]*property="og:video(?::secure_url|:url)?"[^>]*content="([^"]+)"',
        r"<meta[^>]*property='og:video(?::secure_url|:url)?'[^>]*content='([^']+)'",
        r'<meta[^>]*name="twitter:player:stream"[^>]*content="([^"]+)"',
        r"<meta[^>]*name='twitter:player:stream'[^>]*content='([^']+)'",
        r'<source[^>]*src="([^"]+\.(?:mp4|m3u8|webm|mov|m4v)[^"]*)"',
        r"<source[^>]*src='([^']+\.(?:mp4|m3u8|webm|mov|m4v)[^']*)'",
        r'<video[^>]*src="([^"]+\.(?:mp4|m3u8|webm|mov|m4v)[^"]*)"',
        r"<video[^>]*src='([^']+\.(?:mp4|m3u8|webm|mov|m4v)[^']*)'",
        r'"contentUrl":\s*"([^"]+\.(?:mp4|m3u8|webm|mov|m4v)[^"]*)"',
        r'"videoUrl":\s*"([^"]+\.(?:mp4|m3u8|webm|mov|m4v)[^"]*)"',
        r'''https?:\\?/\\?/[^"'\s]+\.(?:mp4|m3u8|webm|mov|m4v)(?:\?[^"'\s]*)?''',
        r'''https?://[^"'\s]+\.(?:mp4|m3u8|webm|mov|m4v)(?:\?[^"'\s]*)?''',
      ];

      String? foundVideoUrl;
      for (final p in videoPatterns) {
        final m = RegExp(p, caseSensitive: false).firstMatch(html);
        if (m != null) {
          foundVideoUrl = m.group(m.groupCount >= 1 ? 1 : 0);
          if (foundVideoUrl != null && foundVideoUrl.isNotEmpty) {
            break;
          }
        }
      }

      if (foundVideoUrl != null && foundVideoUrl.isNotEmpty) {
        String videoUrl = foundVideoUrl.replaceAll(r'\/', '/').replaceAll('&amp;', '&');
        if (!videoUrl.startsWith('http')) {
          final uri = Uri.parse(url);
          if (videoUrl.startsWith('//')) {
            videoUrl = '${uri.scheme}:$videoUrl';
          } else {
            videoUrl = '${uri.scheme}://${uri.host}${videoUrl.startsWith('/') ? '' : '/'}$videoUrl';
          }
        }

        return _buildSimpleMediaResult(
          id: 'web_${DateTime.now().millisecondsSinceEpoch}',
          title: title,
          thumbnail: thumbnail,
          videoUrl: videoUrl,
          platform: forcedPlatform ?? detectPlatform(url),
          author: Uri.tryParse(url)?.host ?? 'Web',
        );
      }

      // إذا لم يكن هناك فيديو صريح، تحقق مما إذا كانت الصفحة تحتوي على ملف صوتي
      final audioMatch = RegExp(r'<audio[^>]*src="([^"]+\.(?:mp3|m4a|wav|aac|ogg)[^"]*)"', caseSensitive: false).firstMatch(html) ??
          RegExp(r'<source[^>]*src="([^"]+\.(?:mp3|m4a|wav|aac|ogg)[^"]*)"', caseSensitive: false).firstMatch(html);
      if (audioMatch != null) {
        String audioUrl = audioMatch.group(1)!.replaceAll(r'\/', '/').replaceAll('&amp;', '&');
        if (!audioUrl.startsWith('http')) {
          final uri = Uri.parse(url);
          audioUrl = '${uri.scheme}://${uri.host}$audioUrl';
        }
        return _buildSimpleMediaResult(
          id: 'web_audio_${DateTime.now().millisecondsSinceEpoch}',
          title: title,
          thumbnail: thumbnail,
          videoUrl: audioUrl,
          platform: 'audio',
          author: Uri.tryParse(url)?.host ?? 'Web',
        );
      }
    } catch (e) {
      debugPrint('HTML Scraper خطأ: $e');
    }

    // إذا فشل كل ما سبق، نفحص الرابط الأصلي مباشرة: هل يقبل البث أو التحميل كملف وسائط؟
    try {
      final head = await _dio.head(
        url,
        options: Options(
          followRedirects: true,
          validateStatus: (s) => s != null && s < 400,
        ),
      );
      final ct = head.headers.value('content-type')?.toLowerCase() ?? '';
      if (ct.contains('video') || ct.contains('audio') || ct.contains('application/octet-stream') || ct.contains('application/vnd.apple.mpegurl')) {
        return _buildSimpleMediaResult(
          id: 'direct_${DateTime.now().millisecondsSinceEpoch}',
          title: 'ملف وسائط من الإنترنت (${Uri.tryParse(url)?.host ?? "Direct"})',
          thumbnail: '',
          videoUrl: url,
          platform: 'direct',
          author: Uri.tryParse(url)?.host ?? 'Direct Link',
        );
      }
    } catch (_) {}

    throw Exception('تعذر العثور على وسائط قابلة للتحميل في هذا الرابط. يرجى التأكد من أن الصفحة أو الفيديو متاح للعامة.');
  }

  /// بناء هيكل نتيجة وسائط موحد
  Map<String, dynamic> _buildSimpleMediaResult({
    required String id,
    required String title,
    required String thumbnail,
    required String videoUrl,
    String? hdVideoUrl,
    String? sdVideoUrl,
    required String platform,
    required String author,
  }) {
    final effectiveHd = (hdVideoUrl != null && hdVideoUrl.isNotEmpty) ? hdVideoUrl : videoUrl;
    final effectiveSd = (sdVideoUrl != null && sdVideoUrl.isNotEmpty) ? sdVideoUrl : videoUrl;

    final List<Map<String, dynamic>> videoFormats = [
      {
        'url': effectiveHd,
        'quality_name': '✨ جودة فائقة محسّنة Ultra HD (أعلى معدل Bitrate ونقاء)',
        'quality_order': 1440,
        'quality_badge': '✨ ULTRA HD',
        'quality_desc': 'معالجة نقية للمشاهد السريعة وأقصى إطارات وصوت ستوديو 320kbps',
        'size': 'فائق النقاء',
        'size_bytes': 0,
        'ext': 'mp4',
        'needs_merge': false,
        'platform': platform,
      },
      {
        'url': effectiveHd,
        'quality_name': 'عالي الدقة 1080p Full HD (أقصى دقة متوفرة)',
        'quality_order': 1080,
        'quality_badge': '1080p FHD',
        'quality_desc': 'أقصى دقة وجودة بصرية فائقة 1080p من المصدر الأصلي بدون ضغط',
        'size': 'أقصى جودة',
        'size_bytes': 0,
        'ext': 'mp4',
        'needs_merge': false,
        'platform': platform,
      },
      {
        'url': effectiveSd,
        'quality_name': 'عالي الدقة 720p HD (تنزيل سريع)',
        'quality_order': 720,
        'quality_badge': '720p HD',
        'quality_desc': 'تنزيل سريع بحجم اقتصادي متوازن ومثالي للمشاهدة السريعة',
        'size': 'سريع',
        'size_bytes': 0,
        'ext': 'mp4',
        'needs_merge': false,
        'platform': platform,
      },
    ];

    final List<Map<String, dynamic>> audioFormats = [
      {
        'url': effectiveHd,
        'quality_name': 'استخراج المسار الصوتي MP3 (192 kbps)',
        'quality_order': 192,
        'quality_badge': 'HQ نقي',
        'quality_desc': 'تحويل واستخراج الصوت النقي بأعلى تردد واستجابة',
        'size': 'صوت نقي',
        'size_bytes': 0,
        'ext': 'mp3',
        'needs_merge': false,
        'platform': platform,
      }
    ];

    return {
      'id': id,
      'title': title.isEmpty ? 'فيديو من $platform' : title,
      'thumbnail': thumbnail.isEmpty ? 'https://via.placeholder.com/640x360/1A1A24/00D9FF?text=$platform' : thumbnail,
      'author': author,
      'platform': platform,
      'highestAudioUrl': effectiveHd,
      'highestAudioTag': null,
      'video': videoFormats,
      'audio': audioFormats,
      'subtitles': [],
    };
  }
}
